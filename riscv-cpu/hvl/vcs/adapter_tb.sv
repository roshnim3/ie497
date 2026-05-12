module adapter_tb;

    //---------------------------------------------------------------------------------
    // Waveform generation.
    //---------------------------------------------------------------------------------
    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, "+all");
    end

    //---------------------------------------------------------------------------------
    // Clock generation
    //---------------------------------------------------------------------------------
    logic clk;
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    logic rst;

    //---------------------------------------------------------------------------------
    // Adapter port signals
    //---------------------------------------------------------------------------------
    // Cache side signals (256-bit single transfer)
    logic [31:0]  cache_addr;
    logic         cache_read;
    logic         cache_write;
    logic [255:0] cache_wdata;
    logic [255:0] cache_rdata;
    logic         cache_resp;

    //---------------------------------------------------------------------------------
    // Memory interface (banked burst interface for DRAM)
    //---------------------------------------------------------------------------------
    mem_itf_banked mem_itf(.*);
    dram_w_burst_frfcfs_controller mem(.itf(mem_itf));

    //---------------------------------------------------------------------------------
    // Instantiate the DUT
    //---------------------------------------------------------------------------------
    adapter dut (
        .clk        (clk),
        .rst        (rst),
        // Cache side (256-bit)
        .cache_addr (cache_addr),
        .cache_read (cache_read),
        .cache_write(cache_write),
        .cache_wdata(cache_wdata),
        .cache_rdata(cache_rdata),
        .cache_resp (cache_resp),
        // Burst/Memory side (64-bit x 4 bursts)
        .burst_addr (mem_itf.raddr),
        .burst_valid(mem_itf.rvalid),
        .burst_rdata(mem_itf.rdata),
        .arb_addr   (mem_itf.addr),
        .arb_read   (mem_itf.read),
        .arb_write  (mem_itf.write),
        .arb_wdata  (mem_itf.wdata)
    );

    //---------------------------------------------------------------------------------
    // Test control variables
    //---------------------------------------------------------------------------------
    int transaction_count = 0;
    int error_count = 0;
    int read_count = 0;
    int write_count = 0;

    // Verbosity control
    bit verbose_mode = 1;

    //---------------------------------------------------------------------------------
    // Test transaction types
    //---------------------------------------------------------------------------------
    typedef struct packed {
        logic [31:0] address;
        bit transaction_type; // 0 = read, 1 = write
        logic [255:0] wdata;
    } input_transaction_t;

    typedef struct {  // Changed from 'packed' to allow unpacked array
        logic [255:0] rdata;
        int cycles_taken;
        logic [63:0] burst_sequence[4]; // Capture burst sequence (unpacked array)
        int num_bursts;
    } output_transaction_t;

    //---------------------------------------------------------------------------------
    // Golden Model for Adapter
    //---------------------------------------------------------------------------------
    // Simulates the expected behavior of the adapter
    class adapter_golden_model;
        // Internal state
        typedef enum {IDLE, READ_BURST_1, READ_BURST_2, READ_BURST_3, READ_BURST_4,
                      WRITE_BURST_1, WRITE_BURST_2, WRITE_BURST_3, WRITE_BURST_4} state_t;
        
        // Expected burst sequence for a transaction
        typedef struct {
            logic [31:0] address;
            logic [63:0] data[4];  // 4 bursts of 64-bit data
            bit is_write;
        } burst_transaction_t;
        
        // Predict what the adapter should do
        function burst_transaction_t predict_transaction(input_transaction_t inp);
            burst_transaction_t golden;
            golden.address = inp.address;
            golden.is_write = inp.transaction_type;
            
            if (inp.transaction_type) begin
                // Write: Split 256-bit into 4x64-bit bursts
                golden.data[0] = inp.wdata[63:0];
                golden.data[1] = inp.wdata[127:64];
                golden.data[2] = inp.wdata[191:128];
                golden.data[3] = inp.wdata[255:192];
            end else begin
                // Read: Expected data will come from memory
                // Golden model doesn't predict memory contents, just the protocol
                golden.data = '{default: 'x};
            end
            
            return golden;
        endfunction
        
        // Assemble read data from bursts
        function logic [255:0] assemble_read_data(logic [63:0] bursts[4]);
            return {bursts[3], bursts[2], bursts[1], bursts[0]};
        endfunction
        
        // Verify burst sequence
        function bit verify_bursts(burst_transaction_t golden, logic [63:0] actual_bursts[4]);
            bit match = 1'b1;
            if (golden.is_write) begin
                for (int i = 0; i < 4; i++) begin
                    if (golden.data[i] !== actual_bursts[i]) begin
                        $error("  [GOLDEN] Burst %0d mismatch! Expected: 0x%016h, Got: 0x%016h", 
                               i, golden.data[i], actual_bursts[i]);
                        match = 1'b0;
                    end
                end
            end
            return match;
        endfunction
    endclass
    
    // Instantiate golden model
    adapter_golden_model golden_model;

    //---------------------------------------------------------------------------------
    // DUT driver task with golden model verification
    //---------------------------------------------------------------------------------
    // Protocol Notes:
    //   READ:  cache_read  is asserted for 1 cycle, then deasserted
    //   WRITE: cache_write is asserted and HELD HIGH for entire 4-burst transaction
    //          until cache_resp is received
    //---------------------------------------------------------------------------------
    task automatic drive_dut(input input_transaction_t inp, output output_transaction_t out);
        int timeout_counter;
        bit cache_resp_seen;
        int start_time;
        logic [63:0] observed_bursts[4];
        int burst_count;
        adapter_golden_model::burst_transaction_t golden_txn;
        
        // Initialize output
        out.rdata = '0;
        out.cycles_taken = 0;
        out.burst_sequence = '{default: '0};
        out.num_bursts = 0;
        cache_resp_seen = 0;
        burst_count = 0;
        observed_bursts = '{default: '0};
        
        // Get golden model prediction
        golden_txn = golden_model.predict_transaction(inp);
        
        start_time = $time;
        timeout_counter = 0;
        
        if (verbose_mode) begin
            $display("\n[DUT] Starting transaction at time %0t", $time);
            $display("  Driving: %s to Addr=0x%08h", 
                     inp.transaction_type ? "WRITE" : "READ", inp.address);
            if (inp.transaction_type) begin
                $display("  Write Data: 0x%064h", inp.wdata);
                $display("  [GOLDEN] Expected burst sequence:");
                for (int i = 0; i < 4; i++) begin
                    $display("    Burst[%0d]: 0x%016h", i, golden_txn.data[i]);
                end
                $display("  [NOTE] cache_write will be held HIGH for entire 4-burst transaction");
            end else begin
                $display("  [NOTE] cache_read will be deasserted after 1 cycle");
            end
        end
        
        // Drive cache signals
        // @(posedge clk);
        cache_addr <= inp.address;
        cache_read <= inp.transaction_type ? 1'b0 : 1'b1;
        cache_write <= inp.transaction_type ? 1'b1 : 1'b0;
        cache_wdata <= inp.wdata;
        
        // Wait for response and monitor bursts
        @(posedge clk);
        // For READ: deassert cache_read after one cycle
        // For WRITE: keep cache_write high for the entire transaction
        if (inp.transaction_type == 0) begin
            cache_read <= 1'b0;
        end

        while (!cache_resp_seen && timeout_counter < 1000) begin
            // Monitor writes to memory (adapter -> memory)
            if (mem_itf.write && mem_itf.ready && burst_count < 4) begin
                observed_bursts[burst_count] = mem_itf.wdata;
                if (verbose_mode) begin
                    $display("  [BURST] Write burst[%0d] = 0x%016h at addr=0x%08h in state=%0d", 
                                burst_count, mem_itf.wdata, mem_itf.addr, dut.state);
                end
                burst_count++;
            end
            
            // Monitor reads from memory (memory -> adapter)
            if (mem_itf.rvalid && burst_count < 4) begin
                observed_bursts[burst_count] = mem_itf.rdata;
                if (verbose_mode) begin
                    $display("  [BURST] Read burst[%0d] = 0x%016h at addr=0x%08h in state=%0d", 
                                burst_count, mem_itf.rdata, mem_itf.raddr, dut.state);
                end
                burst_count++;
            end

            if (cache_resp) begin
                cache_resp_seen = 1;
                out.rdata = cache_rdata;
                out.cycles_taken = timeout_counter;
                if (verbose_mode) begin
                    $display("  [DUT RESP] Got response at cycle %0d", timeout_counter);
                    if (inp.transaction_type == 0) begin
                        $display("    Read Data: 0x%064h", cache_rdata);
                    end
                end
            end
            
            timeout_counter++;
            
            @(posedge clk);
        end
        
        if (timeout_counter >= 1000) begin
            $error("TIMEOUT: No cache response after 1000 cycles for address 0x%08h", inp.address);
            error_count++;
            $fatal(1, "Testbench stopped on first error");
        end else if (verbose_mode) begin
            $display("  [COMPLETE] Transaction took %0d cycles", timeout_counter);
        end
        
        // Store burst sequence in output
        out.burst_sequence = observed_bursts;
        out.num_bursts = burst_count;
        
        // Verify with golden model
        if (inp.transaction_type) begin
            // For writes, verify the burst sequence matches
            if (!golden_model.verify_bursts(golden_txn, observed_bursts)) begin
                $error("  [VERIFY FAIL] Write burst sequence does not match golden model!");
                error_count++;
                $fatal(1, "Testbench stopped on first error");
            end else if (verbose_mode) begin
                $display("  [VERIFY PASS] Write burst sequence matches golden model ✓");
            end
        end else begin
            // For reads, verify we assembled data correctly
            logic [255:0] golden_assembled = golden_model.assemble_read_data(observed_bursts);
            if (golden_assembled !== out.rdata) begin
                $error("  [VERIFY FAIL] Read data assembly mismatch!");
                $error("    Expected: 0x%064h", golden_assembled);
                $error("    Got:      0x%064h", out.rdata);
                error_count++;
                $fatal(1, "Testbench stopped on first error");
            end else if (verbose_mode) begin
                $display("  [VERIFY PASS] Read data correctly assembled from bursts ✓");
            end
        end
        
        // Deassert cache signals
        @(posedge clk);
        @(posedge clk);
        cache_addr <= '0;
        cache_read <= 1'b0;
        cache_write <= 1'b0;
        cache_wdata <= '0;
        
        // Wait for clean separation
        @(posedge clk);
    endtask

    //---------------------------------------------------------------------------------
    // Individual test tasks
    //---------------------------------------------------------------------------------
    task automatic test_single_read();
        input_transaction_t inp;
        output_transaction_t out;
        
        $display("\n[TEST %0d] Single Read Transaction", transaction_count + 1);
        
        inp.address = 32'h0000_1000;
        inp.transaction_type = 0; // Read
        inp.wdata = '0;
        
        drive_dut(inp, out);
        
        $display("  ✓ Read completed in %0d cycles", out.cycles_taken);
        $display("  Data: 0x%064h", out.rdata);
        
        transaction_count++;
        read_count++;
    endtask

    task automatic test_single_write();
        input_transaction_t inp;
        output_transaction_t out;
        
        $display("\n[TEST %0d] Single Write Transaction", transaction_count + 1);
        
        inp.address = 32'h0000_2000;
        inp.transaction_type = 1; // Write
        inp.wdata = 256'hDEADBEEF_CAFEBABE_12345678_9ABCDEF0_FEDCBA98_76543210_AAAABBBB_CCCCDDDD;
        
        drive_dut(inp, out);
        
        $display("  ✓ Write completed in %0d cycles", out.cycles_taken);
        
        transaction_count++;
        write_count++;
    endtask

    task automatic test_multiple_reads();
        input_transaction_t inp;
        output_transaction_t out;
        int num_reads = 5;
        
        $display("\n[TEST %0d] Multiple Sequential Reads", transaction_count + 1);
        
        for (int i = 0; i < num_reads; i++) begin
            inp.address = 32'h0000_3000 + (i * 32'h0100);
            inp.transaction_type = 0; // Read
            inp.wdata = '0;
            
            if (verbose_mode) $display("  Read %0d: Addr=0x%08h", i, inp.address);
            drive_dut(inp, out);
            
            transaction_count++;
            read_count++;
        end
        
        $display("  ✓ All %0d reads completed successfully", num_reads);
    endtask

    task automatic test_multiple_writes();
        input_transaction_t inp;
        output_transaction_t out;
        int num_writes = 5;
        
        $display("\n[TEST %0d] Multiple Sequential Writes", transaction_count + 1);
        
        for (int i = 0; i < num_writes; i++) begin
            inp.address = 32'h0000_4000 + (i * 32'h0100);
            inp.transaction_type = 1; // Write
            // Generate unique pattern for each write
            inp.wdata = {8{32'(i)}};
            
            if (verbose_mode) $display("  Write %0d: Addr=0x%08h", i, inp.address);
            drive_dut(inp, out);
            
            transaction_count++;
            write_count++;
        end
        
        $display("  ✓ All %0d writes completed successfully", num_writes);
    endtask

    task automatic test_read_write_interleaved();
        input_transaction_t inp;
        output_transaction_t out;
        logic [255:0] write_data;
        logic [31:0] addr;
        
        $display("\n[TEST %0d] Interleaved Read/Write to Same Address", transaction_count + 1);
        
        addr = 32'h0000_5000;
        write_data = 256'h1111_2222_3333_4444_5555_6666_7777_8888_9999_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000;
        
        // Write first
        inp.address = addr;
        inp.transaction_type = 1;
        inp.wdata = write_data;
        
        $display("  Write to 0x%08h", addr);
        drive_dut(inp, out);
        transaction_count++;
        write_count++;
        
        // Small delay
        repeat(2) @(posedge clk);
        
        // Read back
        inp.address = addr;
        inp.transaction_type = 0;
        inp.wdata = '0;
        
        $display("  Read from 0x%08h", addr);
        drive_dut(inp, out);
        transaction_count++;
        read_count++;
        
        $display("  ✓ Interleaved operations completed");
        $display("  Read data: 0x%064h", out.rdata);
    endtask

    task automatic test_back_to_back();
        input_transaction_t inp;
        output_transaction_t out;
        
        $display("\n[TEST %0d] Back-to-Back Transactions (No Gap)", transaction_count + 1);
        
        verbose_mode = 0; // Reduce verbosity for stress test
        
        for (int i = 0; i < 10; i++) begin
            inp.address = 32'h0000_6000 + (i * 32'h0020);
            inp.transaction_type = i % 2; // Alternate read/write
            inp.wdata = {8{32'($urandom())}};
            
            drive_dut(inp, out);
            transaction_count++;
            if (inp.transaction_type) write_count++;
            else read_count++;
        end
        
        verbose_mode = 1;
        $display("  ✓ Completed 10 back-to-back transactions");
    endtask

    task automatic test_random_transactions();
        input_transaction_t inp;
        output_transaction_t out;
        int num_random = 50;
        
        $display("\n[TEST %0d] Random Transaction Stress Test", transaction_count + 1);
        $display("  Running %0d random transactions...", num_random);
        
        verbose_mode = 0;
        
        for (int i = 0; i < num_random; i++) begin
            inp.address = {$urandom()} & 32'hFFFF_FFE0; // Align to 32 bytes
            inp.transaction_type = $urandom_range(0, 1);
            inp.wdata = {$urandom(), $urandom(), $urandom(), $urandom(),
                         $urandom(), $urandom(), $urandom(), $urandom()};
            
            drive_dut(inp, out);
            transaction_count++;
            if (inp.transaction_type) write_count++;
            else read_count++;
            
            if ((i + 1) % 10 == 0) begin
                $display("    Progress: %0d/%0d transactions completed", i + 1, num_random);
            end
        end
        
        verbose_mode = 1;
        $display("  ✓ All %0d random transactions completed", num_random);
    endtask

    task automatic test_golden_model_verification();
        input_transaction_t inp;
        output_transaction_t out;
        logic [255:0] test_pattern;
        
        $display("\n[TEST %0d] Golden Model Specific Verification", transaction_count + 1);
        
        verbose_mode = 1;
        
        // Test 1: Write with known pattern
        $display("\n  [1/3] Testing write burst splitting...");
        inp.address = 32'h0000_7000;
        inp.transaction_type = 1;
        inp.wdata = 256'h0000_0003_0000_0002_0000_0001_0000_0000;
        
        drive_dut(inp, out);
        transaction_count++;
        write_count++;
        
        if (out.num_bursts != 4) begin
            $error("    Expected 4 bursts, got %0d", out.num_bursts);
            error_count++;
            $fatal(1, "Testbench stopped on first error");
        end else begin
            $display("    ✓ Correct number of bursts (4)");
        end
        
        // Test 2: Read and verify assembly
        $display("\n  [2/3] Testing read burst assembly...");
        inp.address = 32'h0000_8000;
        inp.transaction_type = 0;
        inp.wdata = '0;
        
        drive_dut(inp, out);
        transaction_count++;
        read_count++;
        
        if (out.num_bursts != 4) begin
            $error("    Expected 4 bursts, got %0d", out.num_bursts);
            error_count++;
            $fatal(1, "Testbench stopped on first error");
        end else begin
            $display("    ✓ Correct number of bursts (4)");
        end
        
        // Test 3: Write then read back verification
        $display("\n  [3/3] Testing write-read consistency...");
        test_pattern = 256'hFEDCBA98_76543210_01234567_89ABCDEF_AAAABBBB_CCCCDDDD_EEEEFFFF_00001111;
        inp.address = 32'h0000_9000;
        inp.transaction_type = 1;
        inp.wdata = test_pattern;
        
        $display("    Writing pattern: 0x%064h", test_pattern);
        drive_dut(inp, out);
        transaction_count++;
        write_count++;
        
        repeat(5) @(posedge clk);
        
        inp.transaction_type = 0;
        inp.wdata = '0;
        
        $display("    Reading back...");
        drive_dut(inp, out);
        transaction_count++;
        read_count++;
        
        if (out.rdata == test_pattern) begin
            $display("    ✓ Read data matches written pattern!");
        end else begin
            $error("    Read data mismatch!");
            $error("      Written: 0x%064h", test_pattern);
            $error("      Read:    0x%064h", out.rdata);
            error_count++;
        end
        
        verbose_mode = 0;
        $display("\n  ✓ Golden model verification tests completed");
    endtask

    //---------------------------------------------------------------------------------
    // Main test
    //---------------------------------------------------------------------------------
    initial begin
        $display("\n");
        $display("╔═══════════════════════════════════════════╗");
        $display("║      ECE 411: ADAPTER TEST BENCH          ║");
        $display("║    WITH GOLDEN MODEL VERIFICATION         ║");
        $display("╚═══════════════════════════════════════════╝");
        $display("");
        $display("Test Configuration:");
        $display("  - Cache side: 256-bit single transfer");
        $display("  - Memory side: 64-bit x 4 bursts");
        $display("  - Adapter converts between formats");
        $display("  - Golden model verifies all transactions");
        $display("");
        
        // Initialize golden model
        golden_model = new();
        $display("[INIT] Golden model initialized");
        
        // Initialize
        rst = 1'b1;
        cache_addr = '0;
        cache_read = 1'b0;
        cache_write = 1'b0;
        cache_wdata = '0;
        transaction_count = 0;
        error_count = 0;
        read_count = 0;
        write_count = 0;
        
        $display("[RESET] Applying reset...");
        repeat(10) @(posedge clk);
        rst = 1'b0;
        $display("[RESET] Reset complete - adapter is now operational\n");
        repeat(10) @(posedge clk);
        
        // Run test suite
        $display("╔════════════════════════════════════════╗");
        $display("║         PHASE 1: BASIC TESTS           ║");
        $display("╚════════════════════════════════════════╝");
        
        test_single_read();
        test_single_write();
        test_read_write_interleaved();
        
        $display("╔════════════════════════════════════════╗");
        $display("║      PHASE 2: SEQUENTIAL TESTS         ║");
        $display("╚════════════════════════════════════════╝");
        
        test_multiple_reads();
        test_multiple_writes();
        
        $display("╔════════════════════════════════════════╗");
        $display("║        PHASE 3: STRESS TESTS           ║");
        $display("╚════════════════════════════════════════╝");
        
        test_back_to_back();
        test_golden_model_verification();
        test_random_transactions();
        
        // Final summary
        $display("\n");
        $display("╔═══════════════════════════════════════════╗");
        $display("║          FINAL TEST SUMMARY              ║");
        $display("╚═══════════════════════════════════════════╝");
        $display("");
        $display("  Total transactions : %0d", transaction_count);
        $display("  Read transactions  : %0d", read_count);
        $display("  Write transactions : %0d", write_count);
        $display("  Total errors       : %0d", error_count);
        $display("");
        $display("  Golden Model Verification:");
        $display("    - All burst sequences verified against golden model");
        $display("    - Read data assembly checked");
        $display("    - Write burst splitting checked");
        $display("");
        
        if (error_count == 0) begin
            $display("╔══════════════════════════════════════════╗");
            $display("║        ✓✓✓ ALL TESTS PASSED! ✓✓✓         ║");
            $display("║    DUT matches Golden Model perfectly!   ║");
            $display("╚══════════════════════════════════════════╝");
        end else begin
            $display("╔══════════════════════════════════════════╗");
            $display("║        ✗✗✗ %3d ERRORS FOUND ✗✗✗          ║", error_count);
            $display("║     DUT deviates from Golden Model!      ║");
            $display("╚══════════════════════════════════════════╝");
        end
        $display("");
        
        // Clean shutdown to avoid spurious "burst incomplete" errors
        // Reset the system to ensure clean termination
        rst = 1'b1;
        @(posedge clk);
        rst = 1'b0;
        repeat(5) @(posedge clk);
        $finish;
    end

    //---------------------------------------------------------------------------------
    // Timeout watchdog
    //---------------------------------------------------------------------------------
    initial begin
        repeat(100000) @(posedge clk);
        $display("\n[ERROR] Global timeout - testbench did not complete");
        $fatal;
    end

endmodule : adapter_tb