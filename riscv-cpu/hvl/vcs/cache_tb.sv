module cache_tb;
    //---------------------------------------------------------------------------------
    // Waveform generation.
    //---------------------------------------------------------------------------------
    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, "+all");
    end

    //---------------------------------------------------------------------------------
    // Cache port signals
    //---------------------------------------------------------------------------------
    logic           clk;
    logic           rst;
    
    // UFP signals
    logic   [31:0]  ufp_addr;
    logic   [3:0]   ufp_rmask;
    logic   [3:0]   ufp_wmask;
    logic   [31:0]  ufp_rdata;
    logic   [31:0]  ufp_wdata;
    logic           ufp_resp;
    
    // DFP signals
    logic   [31:0]  dfp_addr;
    logic           dfp_read;
    logic           dfp_write;
    logic   [255:0] dfp_rdata;
    logic   [255:0] dfp_wdata;
    logic           dfp_resp;

    //---------------------------------------------------------------------------------
    // Instantiate the DUT
    //---------------------------------------------------------------------------------
    cache dut (
        .clk        (clk),
        .rst        (rst),
        .ufp_addr   (ufp_addr),
        .ufp_rmask  (ufp_rmask),
        .ufp_wmask  (ufp_wmask),
        .ufp_rdata  (ufp_rdata),
        .ufp_wdata  (ufp_wdata),
        .ufp_resp   (ufp_resp),
        .dfp_addr   (dfp_addr),
        .dfp_read   (dfp_read),
        .dfp_write  (dfp_write),
        .dfp_rdata  (dfp_rdata),
        .dfp_wdata  (dfp_wdata),
        .dfp_resp   (dfp_resp)
    );

    //---------------------------------------------------------------------------------
    // Clock generation
    //---------------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //---------------------------------------------------------------------------------
    // Transaction types for verification
    //---------------------------------------------------------------------------------
    typedef struct packed {
        logic [31:0] address;
        bit transaction_type; // 0 = read, 1 = write
        logic [3:0] rmask;
        logic [3:0] wmask;
        logic [31:0] wdata;
        logic [255:0] dfp_rdata; // For misses
        bit expected_hit; // Helper to know if we expect hit
    } input_transaction_t;

    typedef struct packed {
        bit caused_writeback;
        bit caused_allocate;
        logic [31:0] ufp_returned_data;
        logic [255:0] dfp_writeback_data;
        logic [31:0] dfp_writeback_addr;
        logic [31:0] dfp_allocate_addr;
    } output_transaction_t;

    //---------------------------------------------------------------------------------
    // Golden model arrays
    //---------------------------------------------------------------------------------
    logic [31:0] data_golden_arrays[4][16][8]; // [way][set][word]
    logic [22:0] tag_golden_arrays[4][16];     // [way][set]
    logic valid_golden_arrays[4][16];          // [way][set]
    logic dirty_golden_arrays[4][16];          // [way][set]
    logic [2:0] plru_golden_array[16];         // [set] - stored as [L2, L1, L0]
    
    //---------------------------------------------------------------------------------
    // Test control variables
    //---------------------------------------------------------------------------------
    int transaction_count = 0;
    int error_count = 0;
    int hit_count = 0;
    int miss_count = 0;
    int writeback_count = 0;
    
    // Verbosity control
    bit verbose_mode = 1;  // Set to 0 to reduce output

    //---------------------------------------------------------------------------------
    // Helper functions
    //---------------------------------------------------------------------------------
    function automatic void init_golden_arrays();
        for (int way = 0; way < 4; way++) begin
            for (int set = 0; set < 16; set++) begin
                valid_golden_arrays[way][set] = 1'b0;
                dirty_golden_arrays[way][set] = 1'b0;
                tag_golden_arrays[way][set] = '0;
                for (int word = 0; word < 8; word++) begin
                    data_golden_arrays[way][set][word] = '0;
                end
            end
        end
        for (int set = 0; set < 16; set++) begin
            plru_golden_array[set] = 3'b000;
        end
        $display("[INIT] Golden arrays initialized - all cache lines invalid");
    endfunction

    // CORRECT PLRU implementation from course slides
    // Tree structure:
    //       L0 (AB/CD)
    //      /         \
    //   L1 (A/B)   L2 (C/D)
    //   /    \      /    \
    // Way0  Way1  Way2  Way3
    //  (A)   (B)   (C)   (D)
    //
    // PLRU bits stored as [L2, L1, L0]
    // L0: 0=AB half more recent, 1=CD half more recent
    // L1: 0=A more recent, 1=B more recent (within AB)
    // L2: 0=C more recent, 1=D more recent (within CD)
    
    function automatic logic [1:0] decode_plru(logic [2:0] plru_bits);
        // Find LEAST recently used way (victim)
        logic L0 = plru_bits[0];
        logic L1 = plru_bits[1];
        logic L2 = plru_bits[2];
        logic [1:0] victim;
        
        if (L0 == 1'b0) begin
            // AB half is more recent, replace from CD half
            if (L2 == 1'b0) begin
                victim = 2'd3; // Way D is LRU in CD half
            end else begin
                victim = 2'd2; // Way C is LRU in CD half
            end
        end else begin
            // CD half is more recent, replace from AB half
            if (L1 == 1'b0) begin
                victim = 2'd1; // Way B is LRU in AB half
            end else begin
                victim = 2'd0; // Way A is LRU in AB half
            end
        end
        
        if (verbose_mode) begin
            $display("    [PLRU] Decode: bits=%b -> victim way=%0d", plru_bits, victim);
        end
        return victim;
    endfunction

    function automatic logic [2:0] update_plru(logic [2:0] current_plru, logic [1:0] way_accessed);
        logic [2:0] new_plru = current_plru;
        
        // Update based on course slide table
        case (way_accessed)
            2'd0: begin // Way A accessed
                new_plru[1] = 1'b0; // L1 = 0 (A more recent than B)
                new_plru[0] = 1'b0; // L0 = 0 (AB more recent than CD)
            end
            2'd1: begin // Way B accessed
                new_plru[1] = 1'b1; // L1 = 1 (B more recent than A)
                new_plru[0] = 1'b0; // L0 = 0 (AB more recent than CD)
            end
            2'd2: begin // Way C accessed
                new_plru[2] = 1'b0; // L2 = 0 (C more recent than D)
                new_plru[0] = 1'b1; // L0 = 1 (CD more recent than AB)
            end
            2'd3: begin // Way D accessed
                new_plru[2] = 1'b1; // L2 = 1 (D more recent than C)
                new_plru[0] = 1'b1; // L0 = 1 (CD more recent than AB)
            end
        endcase
        
        if (verbose_mode) begin
            $display("    [PLRU] Update: way %0d accessed, %b -> %b", way_accessed, current_plru, new_plru);
        end
        return new_plru;
    endfunction

    function automatic int get_cached_addresses(ref logic [31:0] addrs[256]);
        int count = 0;
        for (int set = 0; set < 16; set++) begin
            for (int way = 0; way < 4; way++) begin
                if (valid_golden_arrays[way][set]) begin
                    if (count < 256) begin
                        addrs[count] = {tag_golden_arrays[way][set], set[3:0], 5'b0};
                        count++;
                    end
                end
            end
        end
        return count;
    endfunction

    //---------------------------------------------------------------------------------
    // Input transaction generation
    //---------------------------------------------------------------------------------
    function automatic input_transaction_t generate_input_transaction();
        input_transaction_t inp;
        logic [31:0] cached_addrs[256];
        int local_cached_count;
        bit do_hit;
        
        // Randomize whether to do a hit or miss
        std::randomize(do_hit) with {do_hit dist {0:=25, 1:=75};}; // 75% hits
        
        local_cached_count = get_cached_addresses(cached_addrs);
        
        if (do_hit && local_cached_count > 0) begin
            // Generate a hit
            inp.address = cached_addrs[$urandom_range(0, local_cached_count-1)];
            inp.address[4:2] = $urandom_range(0, 7); // Random word offset
            inp.address[1:0] = 2'b00; // Aligned
            inp.expected_hit = 1'b1;
        end else begin
            // Generate a miss
            inp.address = $urandom();
            inp.address[1:0] = 2'b00; // Aligned
            inp.expected_hit = 1'b0;
        end
        
        // Randomize transaction type
        inp.transaction_type = $urandom_range(0, 1);
        
        if (inp.transaction_type == 0) begin
            // Read
            inp.rmask = 4'b1111;
            inp.wmask = 4'b0000;
            inp.wdata = 32'hDEADBEEF;
        end else begin
            // Write
            inp.rmask = 4'b0000;
            inp.wmask = $urandom() | 4'b0001; // At least one byte
            inp.wdata = $urandom();
        end
        
        // Generate random DFP data for potential miss
        for (int i = 0; i < 8; i++) begin
            inp.dfp_rdata[i*32 +: 32] = $urandom();
        end
        
        return inp;
    endfunction

    //---------------------------------------------------------------------------------
    // Golden cache model
    //---------------------------------------------------------------------------------
    function automatic output_transaction_t golden_cache_do(input_transaction_t inp);
        output_transaction_t out;
        logic [22:0] tag;
        logic [3:0] index;
        logic [4:0] offset;
        logic [1:0] hit_way;
        bit cache_hit;
        string op_type;
        logic [1:0] victim_way;
        
        // Initialize output
        out = '0;
        
        // Parse address
        tag = inp.address[31:9];
        index = inp.address[8:5];
        offset = inp.address[4:0];
        
        op_type = inp.transaction_type ? "WRITE" : "READ";
        
        $display("\n[GOLDEN] Processing %s: Addr=0x%08h (Tag=0x%06h, Set=%0d, Word=%0d)", 
                 op_type, inp.address, tag, index, offset[4:2]);
        
        // Check for hit
        cache_hit = 1'b0;
        hit_way = 2'bxx;
        for (int way = 0; way < 4; way++) begin
            if (valid_golden_arrays[way][index] && 
                tag_golden_arrays[way][index] == tag) begin
                cache_hit = 1'b1;
                hit_way = way[1:0];
                $display("  [HIT] Found in Way %0d", way);
                break;
            end
        end
        
        if (cache_hit) begin
            // Hit case
            hit_count++;
            
            if (inp.transaction_type == 0) begin
                // Read hit
                out.ufp_returned_data = data_golden_arrays[hit_way][index][offset[4:2]];
                $display("  [READ HIT] Returning data: 0x%08h from Way %0d", 
                         out.ufp_returned_data, hit_way);
            end else begin
                // Write hit
                logic [31:0] current_data = data_golden_arrays[hit_way][index][offset[4:2]];
                logic [31:0] new_data = current_data;
                for (int i = 0; i < 4; i++) begin
                    if (inp.wmask[i]) begin
                        new_data[i*8 +: 8] = inp.wdata[i*8 +: 8];
                    end
                end
                data_golden_arrays[hit_way][index][offset[4:2]] = new_data;
                dirty_golden_arrays[hit_way][index] = 1'b1;
                $display("  [WRITE HIT] Updated Way %0d: 0x%08h -> 0x%08h (wmask=%b)", 
                         hit_way, current_data, new_data, inp.wmask);
                $display("  [DIRTY] Set %0d, Way %0d marked dirty", index, hit_way);
            end
            
            // Update PLRU
            plru_golden_array[index] = update_plru(plru_golden_array[index], hit_way);
            
        end else begin
            // Miss case
            miss_count++;
            victim_way = decode_plru(plru_golden_array[index]);
            
            $display("  [MISS] Cache miss - need to allocate");
            $display("  [VICTIM] Selected Way %0d for replacement", victim_way);
            
            // Check if victim is dirty
            if (valid_golden_arrays[victim_way][index] && 
                dirty_golden_arrays[victim_way][index]) begin
                // Writeback needed
                out.caused_writeback = 1'b1;
                out.dfp_writeback_addr = {tag_golden_arrays[victim_way][index], index, 5'b0};
                for (int word = 0; word < 8; word++) begin
                    out.dfp_writeback_data[word*32 +: 32] = 
                        data_golden_arrays[victim_way][index][word];
                end
                writeback_count++;
                $display("  [WRITEBACK] Evicting dirty line from Way %0d", victim_way);
                $display("    WB Addr: 0x%08h (Tag=0x%06h)", 
                         out.dfp_writeback_addr, tag_golden_arrays[victim_way][index]);
            end else if (valid_golden_arrays[victim_way][index]) begin
                $display("  [EVICT] Evicting clean line from Way %0d", victim_way);
            end
            
            // Allocate
            out.caused_allocate = 1'b1;
            out.dfp_allocate_addr = {tag, index, 5'b0};
            $display("  [ALLOCATE] Fetching new line from memory");
            $display("    Fetch Addr: 0x%08h", out.dfp_allocate_addr);
            
            // Update arrays with new line
            valid_golden_arrays[victim_way][index] = 1'b1;
            tag_golden_arrays[victim_way][index] = tag;
            dirty_golden_arrays[victim_way][index] = (inp.transaction_type == 1) ? 1'b1 : 1'b0;
            
            // Install new data
            for (int word = 0; word < 8; word++) begin
                data_golden_arrays[victim_way][index][word] = 
                    inp.dfp_rdata[word*32 +: 32];
            end
            $display("  [INSTALL] New line installed in Way %0d", victim_way);
            
            // Apply write if needed (write allocate)
            if (inp.transaction_type == 1) begin
                logic [31:0] current_data = data_golden_arrays[victim_way][index][offset[4:2]];
                logic [31:0] new_data = current_data;
                for (int i = 0; i < 4; i++) begin
                    if (inp.wmask[i]) begin
                        new_data[i*8 +: 8] = inp.wdata[i*8 +: 8];
                    end
                end
                data_golden_arrays[victim_way][index][offset[4:2]] = new_data;
                $display("  [WRITE ALLOCATE] Applied write: 0x%08h -> 0x%08h", 
                         current_data, new_data);
            end
            
            // Return read data on read miss
            if (inp.transaction_type == 0) begin
                out.ufp_returned_data = inp.dfp_rdata[offset[4:2]*32 +: 32];
                $display("  [READ MISS] Returning data: 0x%08h", out.ufp_returned_data);
            end
            
            // Update PLRU
            plru_golden_array[index] = update_plru(plru_golden_array[index], victim_way);
        end
        
        return out;
    endfunction

    //---------------------------------------------------------------------------------
    // DUT driver task
    //---------------------------------------------------------------------------------
    task automatic drive_dut(input input_transaction_t inp, output output_transaction_t out);
        int timeout_counter;
        bit dfp_write_seen, dfp_read_seen;
        bit ufp_resp_seen;
        int start_time;
        
        // Initialize output
        out = '0;
        dfp_write_seen = 0;
        dfp_read_seen = 0;
        ufp_resp_seen = 0;
        
        start_time = $time;
        
        $display("\n[DUT] Starting transaction at time %0t", $time);
        $display("  Driving: %s to Addr=0x%08h", 
                 inp.transaction_type ? "WRITE" : "READ", inp.address);
        if (inp.transaction_type) begin
            $display("  Write Data: 0x%08h, Mask: %b", inp.wdata, inp.wmask);
        end
        
        // Drive UFP signals
        @(posedge clk);
        ufp_addr <= inp.address;
        ufp_rmask <= inp.rmask;
        ufp_wmask <= inp.wmask;
        ufp_wdata <= inp.wdata;
        
        // Wait for response with proper DFP handling
        timeout_counter = 0;
        while (!ufp_resp_seen && timeout_counter < 1000) begin
            @(posedge clk);
            
            // Check for DFP transactions
            if (dfp_write && !dfp_write_seen) begin
                dfp_write_seen = 1;
                out.caused_writeback = 1'b1;
                out.dfp_writeback_addr = dfp_addr;
                out.dfp_writeback_data = dfp_wdata;
                $display("  [DUT WB] Writeback detected at cycle %0d", timeout_counter);
                $display("    WB Addr: 0x%08h", dfp_addr);
                // Provide memory response
                fork
                    begin
                        dfp_resp <= 1'b0;
                        repeat(10) @(posedge clk);
                        dfp_resp <= 1'b1;
                        @(posedge clk);
                        dfp_resp <= 1'b0;
                        $display("  [MEM] Writeback acknowledged");
                    end
                join_none
            end
            
            if (dfp_read && !dfp_read_seen) begin
                dfp_read_seen = 1;
                out.caused_allocate = 1'b1;
                out.dfp_allocate_addr = dfp_addr;
                $display("  [DUT ALLOC] Allocation request at cycle %0d", timeout_counter);
                $display("    Alloc Addr: 0x%08h", dfp_addr);
                // Provide memory response with data
                fork
                    begin
                        dfp_rdata <= inp.dfp_rdata;
                        dfp_resp <= 1'b0;
                        repeat(10) @(posedge clk);
                        dfp_resp <= 1'b1;
                        @(posedge clk);
                        dfp_resp <= 1'b0;
                        dfp_rdata <= '0;
                        $display("  [MEM] Data provided for allocation");
                    end
                join_none
            end
            
            if (ufp_resp) begin
                ufp_resp_seen = 1;
                out.ufp_returned_data = ufp_rdata;
                $display("  [DUT RESP] Got response at cycle %0d", timeout_counter);
                if (inp.transaction_type == 0) begin
                    $display("    Read Data: 0x%08h", ufp_rdata);
                end
            end
            
            timeout_counter++;
        end
        
        if (timeout_counter >= 1000) begin
            $error("TIMEOUT: No UFP response after 1000 cycles for address 0x%08h", inp.address);
        end else begin
            $display("  [COMPLETE] Transaction took %0d cycles", timeout_counter);
        end
        
        // Wait for all DFP transactions to complete
        if (dfp_read_seen || dfp_write_seen) begin
            wait(dfp_resp == 1'b0);
            @(posedge clk);
        end
        
        // Deassert UFP signals
        @(posedge clk);
        ufp_rmask <= 4'b0000;
        ufp_wmask <= 4'b0000;
        ufp_addr <= '0;
        ufp_wdata <= '0;
        
        // Wait for clean separation
        @(posedge clk);
    endtask

    //---------------------------------------------------------------------------------
    // Comparison function
    //---------------------------------------------------------------------------------
    function automatic void compare_outputs(output_transaction_t golden_out, 
                                           output_transaction_t dut_out,
                                           input_transaction_t inp);
        bit has_error = 0;
        
        $display("\n[VERIFY] Comparing Golden Model vs DUT:");
        
        // Check writeback
        if (golden_out.caused_writeback != dut_out.caused_writeback) begin
            $error("  *** WRITEBACK MISMATCH: Golden=%b, DUT=%b", 
                   golden_out.caused_writeback, dut_out.caused_writeback);
            has_error = 1;
        end else if (golden_out.caused_writeback) begin
            $display("  ✓ Writeback: Both performed writeback");
            if (golden_out.dfp_writeback_addr != dut_out.dfp_writeback_addr) begin
                $error("    *** WB ADDR MISMATCH: Golden=0x%08h, DUT=0x%08h",
                       golden_out.dfp_writeback_addr, dut_out.dfp_writeback_addr);
                has_error = 1;
            end else begin
                $display("    ✓ WB Address matches: 0x%08h", golden_out.dfp_writeback_addr);
            end
        end else begin
            $display("  ✓ Writeback: None needed");
        end
        
        // Check allocation
        if (golden_out.caused_allocate != dut_out.caused_allocate) begin
            $error("  *** ALLOCATE MISMATCH: Golden=%b, DUT=%b",
                   golden_out.caused_allocate, dut_out.caused_allocate);
            has_error = 1;
        end else if (golden_out.caused_allocate) begin
            $display("  ✓ Allocate: Both performed allocation");
            if (golden_out.dfp_allocate_addr != dut_out.dfp_allocate_addr) begin
                $error("    *** ALLOC ADDR MISMATCH: Golden=0x%08h, DUT=0x%08h",
                       golden_out.dfp_allocate_addr, dut_out.dfp_allocate_addr);
                has_error = 1;
            end else begin
                $display("    ✓ Alloc Address matches: 0x%08h", golden_out.dfp_allocate_addr);
            end
        end else begin
            $display("  ✓ Allocate: None needed (hit)");
        end
        
        // Check read data
        if (inp.transaction_type == 0) begin
            if (golden_out.ufp_returned_data !== dut_out.ufp_returned_data) begin
                $error("  *** READ DATA MISMATCH:");
                $error("      Address: 0x%08h", inp.address);
                $error("      Golden:  0x%08h", golden_out.ufp_returned_data);
                $error("      DUT:     0x%08h", dut_out.ufp_returned_data);
                has_error = 1;
            end else begin
                $display("  ✓ Read Data matches: 0x%08h", golden_out.ufp_returned_data);
            end
        end
        
        // Check writeback data if applicable
        if (golden_out.caused_writeback && 
            golden_out.dfp_writeback_data !== dut_out.dfp_writeback_data) begin
            $error("  *** WRITEBACK DATA MISMATCH");
            has_error = 1;
        end
        
        if (has_error) begin
            error_count++;
            $display("\n[ERROR] Transaction %0d FAILED! ❌", transaction_count);
        end else begin
            $display("\n[SUCCESS] Transaction %0d PASSED! ✓", transaction_count);
        end
        
        // Print progress every 100 transactions
        if (!has_error && (transaction_count % 100 == 0) && (transaction_count != 0)) begin
            $display("\n" );
            $display("╔═══════════════════════════════════════╗");
            $display("║     PROGRESS: %5d transactions       ║", transaction_count);
            $display("║     Errors: %3d  |  Hit Rate: %5.1f%%  ║", 
                     error_count, 100.0 * hit_count / (hit_count + miss_count));
            $display("╚═══════════════════════════════════════╝");
            $display("");
        end
    endfunction

    //---------------------------------------------------------------------------------
    // Coverage
    //---------------------------------------------------------------------------------
    covergroup cg @(posedge clk);
        // Basic operation coverage
        writeback_to_pmem: coverpoint dfp_write {
            bins no_write = {0};
            bins write = {1};
        }
        allocate_from_pmem: coverpoint dfp_read {
            bins no_read = {0};
            bins read = {1};
        }
        
        // Set coverage
        all_sets: coverpoint ufp_addr[8:5] iff (ufp_rmask != '0 || ufp_wmask != '0) {
            bins sets[16] = {[0:15]};
        }
        
        // Transaction type coverage
        transaction_type: coverpoint {ufp_rmask != '0, ufp_wmask != '0} {
            bins idle = {2'b00};
            bins read = {2'b10};
            bins write = {2'b01};
            illegal_bins both = {2'b11};
        }
        
        // Hit/miss coverage
        hit_miss: coverpoint {dfp_read || dfp_write} iff (ufp_resp) {
            bins hit = {0};
            bins miss = {1};
        }
        
        // Cross coverage for interesting scenarios
        set_x_type: cross all_sets, transaction_type;
    endgroup : cg

    cg coverage_inst = new();

    //---------------------------------------------------------------------------------
    // Directed test for specific set - ENHANCED VERSION
    //---------------------------------------------------------------------------------
    task automatic test_specific_set(int set_num);
        input_transaction_t inp;
        output_transaction_t golden_out, dut_out;
        
        $display("\n");
        $display("┌─────────────────────────────────────────┐");
        $display("│   Testing Set %2d Exhaustively           │", set_num);
        $display("└─────────────────────────────────────────┘");
        
        // Fill all ways plus one extra to test replacement
        for (int way = 0; way < 5; way++) begin
            $display("\n--- Set %0d, Access %0d (expecting %s) ---", 
                     set_num, way, (way < 4) ? "allocation" : "replacement");
            
            inp.address = {20'($urandom()), set_num[3:0], 5'b00000};
            inp.transaction_type = 0; // Read
            inp.rmask = 4'b1111;
            inp.wmask = 4'b0000;
            inp.wdata = 32'hDEADBEEF;
            for (int i = 0; i < 8; i++) begin
                inp.dfp_rdata[i*32 +: 32] = $urandom();
            end
            inp.expected_hit = 1'b0;
            
            golden_out = golden_cache_do(inp);
            drive_dut(inp, dut_out);
            compare_outputs(golden_out, dut_out, inp);
            transaction_count++;
        end
    endtask

    //---------------------------------------------------------------------------------
    // Stress test with specific patterns
    //---------------------------------------------------------------------------------
    task automatic stress_test_pattern();
        input_transaction_t inp;
        output_transaction_t golden_out, dut_out;
        
        $display("\n");
        $display("╔════════════════════════════════════════╗");
        $display("║       STRESS TEST PATTERNS             ║");
        $display("╚════════════════════════════════════════╝");
        
        // Pattern 1: Back-to-back hits to same line
        $display("\n[PATTERN 1] Back-to-back hits to same cacheline");
        inp.address = 32'h1000_0000;
        for (int i = 0; i < 10; i++) begin
            $display("\n--- Pattern 1: Access %0d ---", i);
            inp.address[4:2] = i[2:0]; // Different words
            inp.transaction_type = i % 2; // Alternate R/W
            inp.rmask = inp.transaction_type ? 4'b0000 : 4'b1111;
            inp.wmask = inp.transaction_type ? 4'b1111 : 4'b0000;
            inp.wdata = $urandom();
            for (int j = 0; j < 8; j++) inp.dfp_rdata[j*32 +: 32] = $urandom();
            
            golden_out = golden_cache_do(inp);
            drive_dut(inp, dut_out);
            compare_outputs(golden_out, dut_out, inp);
            transaction_count++;
        end
        
        // Pattern 2: Conflict misses (same set, different tags)
        $display("\n[PATTERN 2] Conflict misses on Set 0");
        for (int i = 0; i < 10; i++) begin
            $display("\n--- Pattern 2: Conflict %0d ---", i);
            inp.address = {20'($urandom()), 4'b0000, 8'h00}; // All map to set 0
            inp.transaction_type = $urandom_range(0, 1);
            inp.rmask = inp.transaction_type ? 4'b0000 : 4'b1111;
            inp.wmask = inp.transaction_type ? 4'b1111 : 4'b0000;
            inp.wdata = $urandom();
            for (int j = 0; j < 8; j++) inp.dfp_rdata[j*32 +: 32] = $urandom();
            
            golden_out = golden_cache_do(inp);
            drive_dut(inp, dut_out);
            compare_outputs(golden_out, dut_out, inp);
            transaction_count++;
        end
    endtask

    //---------------------------------------------------------------------------------
    // Main test
    //---------------------------------------------------------------------------------
    initial begin
        input_transaction_t inp;
        output_transaction_t golden_out;
        output_transaction_t dut_out;
        static int num_random_transactions = 5000;
        
        $display("\n");
        $display("╔═══════════════════════════════════════════╗");
        $display("║       ECE 411: CACHE TEST BENCH          ║");
        $display("║          STARTING TEST SUITE             ║");
        $display("╚═══════════════════════════════════════════╝");
        $display("");
        $display("Test Configuration:");
        $display("  - Cache: 4-way set associative");
        $display("  - Sets: 16");
        $display("  - Line size: 32 bytes (8 words)");
        $display("  - Replacement: Tree-PLRU");
        $display("  - Policy: Write-back, write-allocate");
        $display("");
        
        // Initialize
        init_golden_arrays();
        rst = 1'b1;
        ufp_rmask = 4'b0000;
        ufp_wmask = 4'b0000;
        ufp_addr = '0;
        ufp_wdata = '0;
        dfp_resp = 1'b0;
        dfp_rdata = '0;
        transaction_count = 0;
        error_count = 0;
        hit_count = 0;
        miss_count = 0;
        writeback_count = 0;
        
        $display("[RESET] Applying reset...");
        repeat(10) @(posedge clk);
        rst = 1'b0;
        $display("[RESET] Reset complete - cache is now operational\n");
        repeat(10) @(posedge clk);
        
        // Phase 1: Directed tests - NOW TESTING ALL 16 SETS
        $display("\n╔═══════════════════════════════════════════╗");
        $display("║   PHASE 1: DIRECTED TESTS (ALL 16 SETS)  ║");
        $display("╚═══════════════════════════════════════════╝");
        for (int set = 0; set < 16; set++) begin  // CHANGED FROM 4 TO 16
            test_specific_set(set);
        end
        
        $display("\n[PHASE 1 COMPLETE] Tested all 16 sets exhaustively");
        $display("  Transactions so far: %0d", transaction_count);
        $display("  Errors so far: %0d", error_count);
        
        // Phase 2: Stress patterns
        $display("\n╔═══════════════════════════════════════════╗");
        $display("║        PHASE 2: STRESS TESTS             ║");
        $display("╚═══════════════════════════════════════════╝");
        stress_test_pattern();
        
        $display("\n[PHASE 2 COMPLETE] Stress patterns tested");
        $display("  Transactions so far: %0d", transaction_count);
        $display("  Errors so far: %0d", error_count);
        
        // Phase 3: Random tests
        $display("\n╔═══════════════════════════════════════════╗");
        $display("║        PHASE 3: RANDOM TESTS             ║");
        $display("╚═══════════════════════════════════════════╝");
        $display("\nRunning %0d random transactions...", num_random_transactions);
        $display("(Detailed output suppressed, progress shown every 100 transactions)\n");
        
        // Reduce verbosity for random tests
        verbose_mode = 0;
        
        for (int i = 0; i < num_random_transactions; i++) begin
            inp = generate_input_transaction();
            golden_out = golden_cache_do(inp);
            drive_dut(inp, dut_out);
            compare_outputs(golden_out, dut_out, inp);
            transaction_count++;
        end
        
        // Restore verbosity
        verbose_mode = 1;
        
        // Final summary
        $display("\n");
        $display("╔═══════════════════════════════════════════╗");
        $display("║           FINAL TEST SUMMARY             ║");
        $display("╚═══════════════════════════════════════════╝");
        $display("");
        $display("  Total transactions : %0d", transaction_count);
        $display("  Total errors       : %0d", error_count);
        $display("  Cache hits         : %0d", hit_count);
        $display("  Cache misses       : %0d", miss_count);
        $display("  Writebacks         : %0d", writeback_count);
        $display("  Hit rate           : %0.1f%%", 100.0 * hit_count / (hit_count + miss_count));
        $display("  Coverage           : %0.2f%%", coverage_inst.get_coverage());
        $display("");
        
        if (error_count == 0) begin
            $display("╔═══════════════════════════════════════════╗");
            $display("║         ✓✓✓ ALL TESTS PASSED! ✓✓✓        ║");
            $display("╚═══════════════════════════════════════════╝");
        end else begin
            $display("╔═══════════════════════════════════════════╗");
            $display("║         ✗✗✗ %3d ERRORS FOUND ✗✗✗         ║", error_count);
            $display("╚═══════════════════════════════════════════╝");
        end
        $display("");
        
        $finish;
    end

endmodule : cache_tb