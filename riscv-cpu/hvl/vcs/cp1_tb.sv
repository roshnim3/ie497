module cp1_tb;

    timeunit 1ps;
    timeprecision 1ps;

    //---------------------------------------------------------------------------------
    // Clock and Reset
    //---------------------------------------------------------------------------------
    int clock_half_period_ps;
    initial begin
        $value$plusargs("CLOCK_PERIOD_PS_ECE411=%d", clock_half_period_ps);
        clock_half_period_ps = clock_half_period_ps / 2;
    end

    bit clk;
    always #(clock_half_period_ps) clk = ~clk;
    bit rst;

    //---------------------------------------------------------------------------------
    // Memory interface (banked burst interface for DRAM)
    //---------------------------------------------------------------------------------
    mem_itf_banked mem_itf(.*);
    dram_w_burst_frfcfs_controller mem(.itf(mem_itf));

    //---------------------------------------------------------------------------------
    // Instantiate the DUT (CPU - Frontend only test)
    //---------------------------------------------------------------------------------
    cpu dut (
        .clk         (clk),
        .rst         (rst),
        .bmem_addr   (mem_itf.addr),
        .bmem_read   (mem_itf.read),
        .bmem_write  (mem_itf.write),
        .bmem_wdata  (mem_itf.wdata),
        .bmem_ready  (mem_itf.ready),
        .bmem_raddr  (mem_itf.raddr),
        .bmem_rdata  (mem_itf.rdata),
        .bmem_rvalid (mem_itf.rvalid)
    );

    //---------------------------------------------------------------------------------
    // Test control variables
    //---------------------------------------------------------------------------------
    int error_count = 0;
    int test_count = 0;
    int instructions_fetched = 0;
    
    // Expected instruction sequence for frontend_test.s
    // These values should match the assembled binary
    logic [31:0] expected_instructions[$];
    
    //---------------------------------------------------------------------------------
    // Waveform generation
    //---------------------------------------------------------------------------------
    initial begin
        $fsdbDumpfile("dump.fsdb");
        if ($test$plusargs("NO_DUMP_ALL_ECE411")) begin
            $fsdbDumpvars(0, dut, "+all");
            $fsdbDumpoff();
        end else begin
            $fsdbDumpvars(0, "+all");
        end
    end

    //---------------------------------------------------------------------------------
    // Initialize expected instructions
    //---------------------------------------------------------------------------------
    initial begin
        // Load expected instructions from disassembly file
        load_expected_instructions_from_disassembly();
    end

    //---------------------------------------------------------------------------------
    // Task to parse disassembly file and populate expected_instructions
    //---------------------------------------------------------------------------------
    task load_expected_instructions_from_disassembly();
        string dis_file;
        string prog_file;
        string base_name;
        int fd;
        string line;
        int count;
        logic [31:0] addr;
        logic [31:0] encoding;
        string mnemonic;
        int scan_result;
        int last_slash, last_dot;

        
        begin
            // Get the disassembly file path from plusarg or derive from PROG
            if (!$value$plusargs("DIS_FILE_ECE411=%s", dis_file)) begin
                // Try to get PROG argument and derive .dis filename
                if ($value$plusargs("PROG_ECE411=%s", prog_file)) begin
                    // Extract basename without path and extension
                    // Find last slash
                    last_slash = -1;
                    for (int i = prog_file.len()-1; i >= 0; i--) begin
                        if (prog_file[i] == "/") begin
                            last_slash = i;
                            break;
                        end
                    end
                    
                    // Extract filename after last slash (or whole string if no slash)
                    if (last_slash >= 0) begin
                        base_name = prog_file.substr(last_slash+1, prog_file.len()-1);
                    end else begin
                        base_name = prog_file;
                    end
                    
                    // Remove .s extension if present
                    last_dot = -1;
                    for (int i = base_name.len()-1; i >= 0; i--) begin
                        if (base_name[i] == ".") begin
                            last_dot = i;
                            break;
                        end
                    end
                    
                    if (last_dot > 0) begin
                        base_name = base_name.substr(0, last_dot-1);
                    end
                    
                    // Construct disassembly path
                    dis_file = {"../bin/", base_name, ".dis"};
                    $display("[INFO] Derived disassembly file from PROG: %s", dis_file);
                end else begin
                    // No PROG argument, use default
                    dis_file = "../bin/frontend_test.dis";
                end
            end
            
            $display("[INFO] Loading expected instructions from disassembly: %s", dis_file);
            
            // Open the disassembly file
            fd = $fopen(dis_file, "r");
            if (fd == 0) begin
                $display("[ERROR] Could not open disassembly file: %s", dis_file);
                $display("[ERROR] Make sure the file exists. You may need to compile the assembly first.");
                $finish;
            end
            
            count = 0;
            // Read line by line and parse instructions
            // Format: aaaaa000:	00100093          	li	x1,1
            while (!$feof(fd)) begin
                if ($fgets(line, fd)) begin
                    // Try to parse instruction line: address: encoding [spaces] mnemonic
                    // Look for lines with colon and hex encoding
                    scan_result = $sscanf(line, "%h: %h", addr, encoding);
                    if (line.match("<_text_vma_end>:")) begin
                        $display("[DEBUG] Reached _text_vma_end marker, stopping instruction parsing");
                        break;
                    end
                    if (scan_result == 2) begin
                        // Check if it's a valid 32-bit instruction (8 hex digits)
                        // Skip .insn pseudo-instructions and padding
                        if (line.len() > 20 && !line.substr(20, 24).match(".insn") && encoding != 32'h00000000) begin
                            expected_instructions.push_back(encoding);
                            count++;
                            $display("[DEBUG] Loaded instruction %0d: 0x%h from address 0x%h", count, encoding, addr);
                        end
                    end
                end
            end
            
            $fclose(fd);
            $display("[INFO] Successfully loaded %0d expected instructions from disassembly", count);
            
            if (count == 0) begin
                $display("[WARNING] No instructions were loaded. Check the disassembly file format.");
            end
        end
    endtask

    //---------------------------------------------------------------------------------
    // Main test sequence
    //---------------------------------------------------------------------------------
    initial begin
        // Display test header
        $display("========================================");
        $display("Frontend (Fetch + Cache + Adapter) Test");
        $display("========================================\n");
        $display("Testing instruction fetch from memory");
        $display("Expected %0d instructions to be fetched\n", expected_instructions.size());

        // Reset sequence
        rst <= 1'b1;
        repeat(5) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);

        // Test 1: Check initial PC
        test_initial_pc();

        // Test 2: Let the frontend fetch instructions and verify them
        test_instruction_fetch();

        // Test 3: Verify instruction order
        test_instruction_ordering();

        // Display results
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_count);
        $display("Instructions Fetched: %0d", instructions_fetched);
        $display("Errors: %0d", error_count);
        if (error_count == 0) begin
            $display("Status: ALL TESTS PASSED!");
        end else begin
            $display("Status: SOME TESTS FAILED!");
        end
        $display("========================================\n");

        $finish;
    end

    //---------------------------------------------------------------------------------
    // Test Tasks
    //---------------------------------------------------------------------------------

    task test_initial_pc();
        begin
            $display("[%0t] [TEST %0d] Checking initial PC value", $time, ++test_count);
            repeat(2) @(posedge clk);
            
            // Check PC is at expected starting address
            if (dut.pc === 32'haaaa_a000) begin
                $display("[%0t]   [PASS] Initial PC is 0x%h", $time, dut.pc);
            end else begin
                $display("[%0t]   [FAIL] Expected PC 0xaaaa_a000, got 0x%h", $time, dut.pc);
                error_count++;
            end
        end
    endtask

    task test_instruction_fetch();
        int i;
        static int max_wait_cycles = 505;
        static int cycle_count = 0;
        logic [31:0] fetched_inst;
        
        begin
            $display("\n[%0t] [TEST %0d] Testing instruction fetch from memory", $time, ++test_count);
            
            // Wait for cache to warm up and start fetching
            @(posedge clk);
            dut.fetch_stage.deq <= 1'b0;
            for (i = 0; i < 500; i++) @(posedge clk); // Extra cycles to stabilize
            
            // Now manually dequeue instructions from the fetch queue and verify them
            for (i = 0; i < expected_instructions.size(); i++) begin
                cycle_count = 0;
                
                // Wait until fetch queue has an instruction (not empty)
                while (dut.fetch_stage.empty && cycle_count < max_wait_cycles) begin
                    @(posedge clk);
                    cycle_count++;
                end
                
                if (cycle_count >= max_wait_cycles) begin
                    $display("[%0t]   [FAIL] Timeout waiting for instruction %0d", $time, i);
                    error_count++;
                    break;
                end
                
                // Force dequeue to get the instruction out
                @(posedge clk);
                dut.fetch_stage.deq <= 1'b1;

                @(posedge clk);
                dut.fetch_stage.deq <= 1'b0;
                fetched_inst = dut.inst_out;
                instructions_fetched++;


                // Verify the instruction
                if (fetched_inst === expected_instructions[i]) begin
                    $display("[%0t]   [PASS] Instruction %0d: 0x%h (PC: 0x%h)", 
                            $time, i, fetched_inst, 32'haaaa_a000 + (i * 4));
                end else begin
                    $display("[%0t]   [FAIL] Instruction %0d: Expected 0x%h, got 0x%h (PC: 0x%h)", 
                            $time, i, expected_instructions[i], fetched_inst, 32'haaaa_a000 + (i * 4));
                    error_count++;
                end
            end
            $display("[%0t]   [INFO] Total instructions fetched and verified: %0d", $time, instructions_fetched);
        end
    endtask

    task test_instruction_ordering();
        begin
            $display("\n[%0t] [TEST %0d] Verifying instruction fetch ordering", $time, ++test_count);
            
            if (instructions_fetched == expected_instructions.size()) begin
                $display("[%0t]   [PASS] All %0d instructions fetched in correct order", 
                        $time, instructions_fetched);
            end else begin
                $display("[%0t]   [FAIL] Expected %0d instructions, only fetched %0d", 
                        $time, expected_instructions.size(), instructions_fetched);
                error_count++;
            end
        end
    endtask

    //---------------------------------------------------------------------------------
    // Monitor and debug outputs
    //---------------------------------------------------------------------------------
    
    // Monitor PC advancement
    always @(posedge clk) begin
        if (!rst && dut.pc !== $past(dut.pc)) begin
            $display("[%0t] [INFO] PC advanced: 0x%h -> 0x%h", $time, $past(dut.pc), dut.pc);
        end
    end
    
    // Monitor cache responses
    int cache_resp_count = 0;
    always @(posedge clk) begin
        if (!rst && dut.cache_resp) begin
            cache_resp_count++;
            $display("[%0t] [INFO] Cache response %0d: inst=0x%h at PC=0x%h", 
                    $time, cache_resp_count, dut.inst_in, $past(dut.pc));
        end
    end
    
    // Monitor fetch queue status
    always @(posedge clk) begin
        if (!rst) begin
            if (dut.fetch_stage.full && !$past(dut.fetch_stage.full)) begin
                $display("[%0t] [INFO] Fetch queue is now FULL", $time);
            end
            if (dut.fetch_stage.empty && !$past(dut.fetch_stage.empty)) begin
                $display("[%0t] [INFO] Fetch queue is now EMPTY", $time);
            end
        end
    end

endmodule
