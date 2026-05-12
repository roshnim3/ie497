// ===============================================================
// top_tb_pipelined.sv
// Pipeline-aware testbench for 2-stage cache (s0, s1)
// Hit latency: N+1. Throughput: 1 access/cycle on hits.
// Writes: pipeline stalls 1 cycle to complete write before s0->s1.
// Misses: WB (if needed) -> Alloc -> cpu_pending wait 1 cycle -> resp.
// Author: you, plus a slightly grumpy assistant.
// ===============================================================

`timescale 1ns/1ps

// Uncomment to disable hierarchical probes if your DUT internals rename
`define TB_PROBES 1

module ppcache_tb_v2;
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
    ppcache dut (
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
        bit          transaction_type; // 0 = read, 1 = write
        logic [3:0]  rmask;
        logic [3:0]  wmask;
        logic [31:0] wdata;
        logic [255:0] dfp_rdata; // For misses
        bit          expected_hit; // Helper to know if we expect hit
    } input_transaction_t;

    typedef struct packed {
        bit           caused_writeback;
        bit           caused_allocate;
        logic [31:0]  ufp_returned_data;
        logic [255:0] dfp_writeback_data;
        logic [31:0]  dfp_writeback_addr;
        logic [31:0]  dfp_allocate_addr;
        int           issue_cycle;
        int           exp_resp_cycle;   // expected response cycle (filled by TB)
        int           alloc_resp_cycle; // cycle when TB asserted dfp_resp for alloc
        bit           timing_error;     // <-- added: indicates timing check failure
    } output_transaction_t;

    //---------------------------------------------------------------------------------
    // Golden model arrays
    //---------------------------------------------------------------------------------
    logic [31:0] data_golden_arrays[4][16][8]; // [way][set][word]
    logic [22:0] tag_golden_arrays[4][16];     // [way][set]
    logic        valid_golden_arrays[4][16];   // [way][set]
    logic        dirty_golden_arrays[4][16];   // [way][set]
    logic [2:0]  plru_golden_array[16];        // [set] - [L2, L1, L0]

    //---------------------------------------------------------------------------------
    // Test control variables
    //---------------------------------------------------------------------------------
    int transaction_count = 0;
    int error_count = 0;
    int hit_count = 0;
    int miss_count = 0;
    int writeback_count = 0;

    // Verbosity control
    bit verbose_mode = 1'b1;  // Set to 0 to reduce output

    // Global cycle counter for assertions/timestamps
    int global_cycle;
    always_ff @(posedge clk) begin
        if (rst) global_cycle <= 0;
        else     global_cycle <= global_cycle + 1;
    end

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

    // PLRU helpers (same as your original)
    function automatic logic [1:0] decode_plru(logic [2:0] plru_bits);
        logic L0 = plru_bits[0];
        logic L1 = plru_bits[1];
        logic L2 = plru_bits[2];
        logic [1:0] victim;
        if (L0 == 1'b0) begin
            victim = (L2 == 1'b0) ? 2'd3 : 2'd2;
        end else begin
            victim = (L1 == 1'b0) ? 2'd1 : 2'd0;
        end
        if (verbose_mode) $display("    [PLRU] Decode: bits=%b -> victim way=%0d", plru_bits, victim);
        return victim;
    endfunction

    function automatic logic [2:0] update_plru(logic [2:0] current_plru, logic [1:0] way_accessed);
        logic [2:0] new_plru = current_plru;
        case (way_accessed)
            2'd0: begin new_plru[1]=1'b0; new_plru[0]=1'b0; end
            2'd1: begin new_plru[1]=1'b1; new_plru[0]=1'b0; end
            2'd2: begin new_plru[2]=1'b0; new_plru[0]=1'b1; end
            2'd3: begin new_plru[2]=1'b1; new_plru[0]=1'b1; end
        endcase
        if (verbose_mode) $display("    [PLRU] Update: way %0d accessed, %b -> %b", way_accessed, current_plru, new_plru);
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
        std::randomize(do_hit) with {do_hit dist {0:=25, 1:=75};}; // 75% hits
        local_cached_count = get_cached_addresses(cached_addrs);
        if (do_hit && local_cached_count > 0) begin
            inp.address = cached_addrs[$urandom_range(0, local_cached_count-1)];
            inp.address[4:2] = $urandom_range(0, 7);
            inp.address[1:0] = 2'b00;
            inp.expected_hit = 1'b1;
        end else begin
            inp.address = $urandom();
            inp.address[1:0] = 2'b00;
            inp.expected_hit = 1'b0;
        end
        inp.transaction_type = $urandom_range(0, 1);
        if (inp.transaction_type == 0) begin
            inp.rmask = 4'b1111;
            inp.wmask = 4'b0000;
            inp.wdata = 32'hDEADBEEF;
        end else begin
            inp.rmask = 4'b0000;
            inp.wmask = ($urandom() | 4'b0001);
            inp.wdata = $urandom();
        end
        for (int i = 0; i < 8; i++) inp.dfp_rdata[i*32 +: 32] = $urandom();
        return inp;
    endfunction

    //---------------------------------------------------------------------------------
    // Golden cache model (unchanged behaviorally)
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

        out = '0;
        tag = inp.address[31:9];
        index = inp.address[8:5];
        offset = inp.address[4:0];
        op_type = inp.transaction_type ? "WRITE" : "READ";

        if (verbose_mode) begin
            $display("\n[GOLDEN] %s: Addr=0x%08h (Tag=0x%06h, Set=%0d, Word=%0d)",
                     op_type, inp.address, tag, index, offset[4:2]);
        end

        cache_hit = 1'b0;
        hit_way = 2'bxx;
        for (int way = 0; way < 4; way++) begin
            if (valid_golden_arrays[way][index] && tag_golden_arrays[way][index] == tag) begin
                cache_hit = 1'b1; hit_way = way[1:0]; break;
            end
        end

        if (cache_hit) begin
            hit_count++;
            if (inp.transaction_type == 0) begin
                out.ufp_returned_data = data_golden_arrays[hit_way][index][offset[4:2]];
            end else begin
                logic [31:0] current_data = data_golden_arrays[hit_way][index][offset[4:2]];
                logic [31:0] new_data = current_data;
                for (int i = 0; i < 4; i++) if (inp.wmask[i]) new_data[i*8 +: 8] = inp.wdata[i*8 +: 8];
                data_golden_arrays[hit_way][index][offset[4:2]] = new_data;
                dirty_golden_arrays[hit_way][index] = 1'b1;
            end
            plru_golden_array[index] = update_plru(plru_golden_array[index], hit_way);
        end else begin
            miss_count++;
            victim_way = decode_plru(plru_golden_array[index]);

            if (valid_golden_arrays[victim_way][index] && dirty_golden_arrays[victim_way][index]) begin
                out.caused_writeback = 1'b1;
                out.dfp_writeback_addr = {tag_golden_arrays[victim_way][index], index, 5'b0};
                for (int word = 0; word < 8; word++)
                    out.dfp_writeback_data[word*32 +: 32] = data_golden_arrays[victim_way][index][word];
                writeback_count++;
            end
            out.caused_allocate = 1'b1;
            out.dfp_allocate_addr = {tag, index, 5'b0};

            // Install fetched line
            valid_golden_arrays[victim_way][index] = 1'b1;
            tag_golden_arrays[victim_way][index] = tag;
            dirty_golden_arrays[victim_way][index] = (inp.transaction_type == 1);
            for (int word = 0; word < 8; word++)
                data_golden_arrays[victim_way][index][word] = inp.dfp_rdata[word*32 +: 32];

            if (inp.transaction_type == 1) begin
                logic [31:0] cur = data_golden_arrays[victim_way][index][offset[4:2]];
                logic [31:0] nxt = cur;
                for (int i = 0; i < 4; i++) if (inp.wmask[i]) nxt[i*8 +: 8] = inp.wdata[i*8 +: 8];
                data_golden_arrays[victim_way][index][offset[4:2]] = nxt;
            end
            if (inp.transaction_type == 0) begin
                out.ufp_returned_data = inp.dfp_rdata[offset[4:2]*32 +: 32];
            end
            plru_golden_array[index] = update_plru(plru_golden_array[index], victim_way);
        end
        return out;
    endfunction

    // --------------------------------------------------------------------------------
    // Assertions and simple X/Z checks
    // --------------------------------------------------------------------------------
    // No X/Z on outputs observed by CPU when ufp_resp is high
    property no_x_on_resp_p;
        @(posedge clk) disable iff (rst)
        ufp_resp |-> (!$isunknown(ufp_rdata));
    endproperty

    // sample global_cycle into a local to avoid non-sampled variable lint
    assert_no_x_on_resp:
    assert property (no_x_on_resp_p) else begin
        int gc = global_cycle;
        $error("[ASSERT] X/Z detected on ufp_rdata when ufp_resp=1 at cycle %0d", gc);
    end

`ifdef TB_PROBES
    // Optional: print stage state each cycle
    always_ff @(posedge clk) begin
        if (!rst) begin
            $display("[DUT@%0d] stall=%0b hit=%0b ufp=%0b dfp=%0b state=%0d evictw= %0d hitw = %0d| s1={tag=%h idx=%0d off=%0d w=%0b mask=%b}",
                global_cycle,
                dut.stall, dut.hit && dut.s1.valid, ufp_resp, dfp_resp, dut.state, dut.evict_way, dut.hit_way,
                dut.s1.tag, dut.s1.index, dut.s1.offset, dut.s1.write, dut.s1.mask);
        end
    end
`endif

    //---------------------------------------------------------------------------------
    // DUT driver task (pipeline-aware)
    //  - Drives request for exactly 1 cycle (samples into s0)
    //  - For writes: inserts a 1-cycle bubble after issuing
    //  - For misses: services WB/Alloc with dfp_resp and enforces N+2 CPU resp
    //---------------------------------------------------------------------------------
    task automatic drive_dut(input input_transaction_t inp, output output_transaction_t out);
        bit dfp_write_seen, dfp_read_seen;
        bit ufp_resp_seen;
        int start_cycle;
        int cycles_waited;
        int alloc_dfp_resp_cycle;
        bit is_write = inp.transaction_type;
        bit is_read  = !inp.transaction_type;

        // added timing bookkeeping
        bit timing_error;
        bit miss_observed;

        // init
        out = '0;
        dfp_write_seen = 1'b0;
        dfp_read_seen  = 1'b0;
        ufp_resp_seen  = 1'b0;
        start_cycle    = global_cycle;
        timing_error   = 1'b0;
        miss_observed  = 1'b0;
        out.alloc_resp_cycle = -1; // sentinel: never saw alloc dfp_resp yet

        // Drive one-cycle request into s0
        @(posedge clk);
        ufp_addr  <= inp.address;
        ufp_rmask <= inp.rmask;
        ufp_wmask <= inp.wmask;
        ufp_wdata <= inp.wdata;
        out.issue_cycle = global_cycle + 1; 

        if (verbose_mode) begin
            $display("\n[DUT] Issue @%0d: %s Addr=0x%08h wmask=%b rmask=%b wdata=0x%08h",
                out.issue_cycle, is_write ? "WRITE" : "READ",
                inp.address, inp.wmask, inp.rmask, inp.wdata);
        end

        // Deassert after one cycle to allow next request later
        @(posedge clk);
        ufp_addr  <= '0;
        ufp_rmask <= 4'b0000;
        ufp_wmask <= 4'b0000;
        ufp_wdata <= '0;

        // If write, insert mandatory 1-cycle bubble (cannot read/write same single-ported SRAM)
        if (is_write) begin
            if (verbose_mode) $display("[DUT] Inserting 1-cycle bubble after write @%0d", global_cycle);
            @(posedge clk);
        end

        // Now wait for activity, service DFP, and capture response
        alloc_dfp_resp_cycle = -1;
        cycles_waited = 0;

        while (!ufp_resp_seen && cycles_waited < 250) begin
            // @(posedge clk);

            // Check for DFP transactions
            if (dfp_write && !dfp_write_seen) begin
                dfp_write_seen = 1'b1;
                out.caused_writeback = 1'b1;
                out.dfp_writeback_addr = dfp_addr;
                out.dfp_writeback_data = dfp_wdata;
                if (verbose_mode) begin
                    $display("  [MEM] WB observed @%0d addr=0x%08h; ack after 10 cycles", global_cycle, dfp_addr);
                end
                fork
                    begin
                        dfp_resp <= 1'b0;
                        repeat(10) @(posedge clk);
                        dfp_resp <= 1'b1;
                        @(posedge clk);
                        dfp_resp <= 1'b0;
                        if (verbose_mode) $display("  [MEM] WB ack complete @%0d", global_cycle);
                    end
                join_none
            end

            if (dfp_read && !dfp_read_seen) begin
                dfp_read_seen = 1'b1;
                miss_observed = 1'b1; // TRUE miss observed via DFP allocate
                out.caused_allocate = 1'b1;
                out.dfp_allocate_addr = dfp_addr;
                if (verbose_mode) begin
                    $display("  [MEM] ALLOC read observed @%0d addr=0x%08h; respond with line after 10 cycles", global_cycle, dfp_addr);
                end
                // Provide memory response with data
                fork
                    begin
                        dfp_rdata <= inp.dfp_rdata;
                        dfp_resp  <= 1'b0;
                        repeat(10) @(posedge clk);
                        dfp_resp  <= 1'b1;
                        alloc_dfp_resp_cycle = global_cycle + 1;
                        out.alloc_resp_cycle = alloc_dfp_resp_cycle;
                        @(posedge clk);
                        dfp_resp  <= 1'b0;
                        dfp_rdata <= '0;
                        if (verbose_mode) $display("  [MEM] ALLOC data supplied @%0d", out.alloc_resp_cycle);
                    end
                join_none
            end

            if (ufp_resp) begin
                ufp_resp_seen = 1'b1;
                out.ufp_returned_data = ufp_rdata;
                if (verbose_mode) begin
                    $display("  [DUT RESP] ufp_resp @%0d data=0x%08h", global_cycle, ufp_rdata);
                end
                out.exp_resp_cycle = global_cycle;
            end

            cycles_waited++;
            @(posedge clk);
        end

        if (!ufp_resp_seen) begin
            $error("TIMEOUT: No ufp_resp after %0d cycles for address 0x%08h", cycles_waited, inp.address);
            timing_error = 1'b1;
        end else if (miss_observed) begin
            // Miss timing: response must be at alloc_resp_cycle + 2
            if (out.alloc_resp_cycle < 0) begin
                $error("[TIMING] Miss observed but alloc_resp_cycle not captured (addr=%08h)", inp.address);
                timing_error = 1'b1;
            end else begin
                int expected = out.alloc_resp_cycle + 2;
                if (out.exp_resp_cycle !== expected) begin
                    $error("[TIMING] Miss timing FAIL: alloc_resp @%0d expected CPU resp @%0d got @%0d (addr=%08h)",
                           out.alloc_resp_cycle, expected, out.exp_resp_cycle, inp.address);
                    timing_error = 1'b1;
                end else if (verbose_mode) begin
                    $display("  [TIMING] Miss timing PASS", out.alloc_resp_cycle, out.exp_resp_cycle);
                end
            end
        end else begin
            // Hit timing: response must be at issue_cycle + 1
            int expected = out.issue_cycle + 1;
            if (out.exp_resp_cycle !== expected) begin
                $error("[TIMING] Hit timing fail: issued @%0d expected resp @%0d got @%0d (addr=%08h)",
                       out.issue_cycle, expected, out.exp_resp_cycle, inp.address);
                timing_error = 1'b1;
            end else if (verbose_mode) begin
                $display("  [TIMING] Hit timing OK (N+1): %0d -> %0d", out.issue_cycle, out.exp_resp_cycle);
            end
        end

        out.timing_error = timing_error;

        // Wait for all DFP transactions to complete
        if (dfp_read_seen || dfp_write_seen) begin
            wait(dfp_resp == 1'b0);
            @(posedge clk);
        end

        // Extra bubble only when a miss was observed (cpu_pending style)
        if (miss_observed) @(posedge clk);

        // Clean separation
        @(posedge clk);
    endtask

    //---------------------------------------------------------------------------------
    // Comparison function (unchanged functional checks + timing error gate)
    //---------------------------------------------------------------------------------
    function automatic void compare_outputs(output_transaction_t golden_out, 
                                           output_transaction_t dut_out,
                                           input_transaction_t inp);
        bit has_error = 1'b0;

        $display("\n[VERIFY] Compare Golden vs DUT:");

        // Timing first
        if (dut_out.timing_error) begin
            has_error = 1'b1;
            $display("  *** TIMING CHECK FAILED for addr=0x%08h", inp.address);
        end

        // Check writeback
        if (golden_out.caused_writeback != dut_out.caused_writeback) begin
            $error("  *** WRITEBACK MISMATCH: Golden=%b, DUT=%b", 
                   golden_out.caused_writeback, dut_out.caused_writeback);
            has_error = 1'b1;
        end else begin
            $display("  ✓ Writeback decision matches: %0b", dut_out.caused_writeback);
        end
        
        if (golden_out.caused_writeback) begin
            if (golden_out.dfp_writeback_addr !== dut_out.dfp_writeback_addr) begin
                $error("    *** WB ADDR MISMATCH: Golden=0x%08h, DUT=0x%08h",
                       golden_out.dfp_writeback_addr, dut_out.dfp_writeback_addr);
                has_error = 1'b1;
            end
        end
        
        // Check allocation
        if (golden_out.caused_allocate != dut_out.caused_allocate) begin
            $error("  *** ALLOCATE MISMATCH: Golden=%b, DUT=%b",
                   golden_out.caused_allocate, dut_out.caused_allocate);
            has_error = 1'b1;
        end else begin
            $display("  ✓ Allocate decision matches: %0b", dut_out.caused_allocate);
        end
        
        if (golden_out.caused_allocate) begin
            if (golden_out.dfp_allocate_addr !== dut_out.dfp_allocate_addr) begin
                $error("    *** ALLOC ADDR MISMATCH: Golden=0x%08h, DUT=0x%08h",
                       golden_out.dfp_allocate_addr, dut_out.dfp_allocate_addr);
                has_error = 1'b1;
            end
        end
        
        // Check read data
        if (inp.transaction_type == 0) begin
            if (golden_out.ufp_returned_data !== dut_out.ufp_returned_data) begin
                $error("  *** READ DATA MISMATCH:");
                $error("      Address: 0x%08h", inp.address);
                $error("      Golden:  0x%08h", golden_out.ufp_returned_data);
                $error("      DUT:     0x%08h", dut_out.ufp_returned_data);
                has_error = 1'b1;
            end else begin
                $display("  ✓ Read data matches: 0x%08h", dut_out.ufp_returned_data);
            end
        end

        if (has_error) begin
            error_count++;
            $display("[RESULT] Transaction %0d FAILED ❌", transaction_count);
            $fatal(1);
        end else begin
            $display("[RESULT] Transaction %0d PASSED ✓", transaction_count);
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
            inp.address = {20'($urandom()), set_num[3:0], 5'b00000};
            inp.transaction_type = 1'b0; // Read
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
        // Ensure line resident by forcing an allocate miss read once
        begin
            input_transaction_t first;
            output_transaction_t g0, d0;
            first = inp;
            first.transaction_type = 1'b0;
            first.rmask = 4'b1111; first.wmask = 4'b0000;
            first.expected_hit = 1'b0;
            for (int j = 0; j < 8; j++) first.dfp_rdata[j*32 +: 32] = $urandom();
            g0 = golden_cache_do(first);
            drive_dut(first, d0);
            compare_outputs(g0, d0, first);
            transaction_count++;
        end
        for (int i = 0; i < 10; i++) begin
            inp.address[4:2] = i[2:0]; // Different words
            inp.transaction_type = (i % 2); // Alternate R/W
            inp.rmask = inp.transaction_type ? 4'b0000 : 4'b1111;
            inp.wmask = inp.transaction_type ? 4'b1111 : 4'b0000;
            inp.wdata = $urandom();
            for (int j = 0; j < 8; j++) inp.dfp_rdata[j*32 +: 32] = $urandom();
            inp.expected_hit = 1'b1;

            golden_out = golden_cache_do(inp);
            drive_dut(inp, dut_out);
            compare_outputs(golden_out, dut_out, inp);
            transaction_count++;
        end
        
        // Pattern 2: Conflict misses (random sets and tags)
        $display("\n[PATTERN 2] Conflict-style random traffic");
        for (int i = 0; i < 10; i++) begin
            inp.address = {20'($urandom()), 4'b0000, 8'h00}; // All map to set 0
            inp.transaction_type = $urandom_range(0, 1);
            inp.rmask = inp.transaction_type ? 4'b0000 : 4'b1111;
            inp.wmask = inp.transaction_type ? 4'b1111 : 4'b0000;
            inp.wdata = $urandom();
            for (int j = 0; j < 8; j++) inp.dfp_rdata[j*32 +: 32] = $urandom();
            inp.expected_hit = 1'b0;
            
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
        static int num_random_transactions = 1000;
        
        $display("\n");
        $display("╔═══════════════════════════════════════════╗");
        $display("║       ECE 411: PIPELINED CACHE TB        ║");
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
        ufp_addr  = '0;
        ufp_wdata = '0;
        dfp_resp  = 1'b0;
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
        
        // Phase 1: Directed tests - ALL 16 SETS
        $display("\n╔═══════════════════════════════════════════╗");
        $display("║   PHASE 1: DIRECTED TESTS (ALL 16 SETS)  ║");
        $display("╚═══════════════════════════════════════════╝");
        for (int set = 0; set < 16; set++) begin
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
        verbose_mode = 1'b1;
        
        for (int i = 0; i < num_random_transactions; i++) begin
            inp = generate_input_transaction();
            golden_out = golden_cache_do(inp);
            drive_dut(inp, dut_out);
            compare_outputs(golden_out, dut_out, inp);
            transaction_count++;
        end
        
        // Restore verbosity
        verbose_mode = 1'b1;
        
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

endmodule : ppcache_tb_v2
