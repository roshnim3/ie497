module freelist_tb;
    import ooo_types::*;

    // Clock and reset
    logic clk;
    logic rst;
    
    // Inputs
    logic       flush;
    logic       alloc_req;
    logic       free_req;
    logic [5:0] free_reg;
    rat_entry_t rrt_in [31:0];
    
    // Outputs
    logic [5:0] alloc_reg;
    logic       alloc_valid;
    logic       full;
    logic       empty;

    // Instantiate the freelist module
    freelist dut (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .alloc_req(alloc_req),
        .free_req(free_req),
        .free_reg(free_reg),
        .rrt_in(rrt_in),
        .alloc_reg(alloc_reg),
        .alloc_valid(alloc_valid),
        .full(full),
        .empty(empty)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test variables
    int test_num = 0;
    int passed = 0;
    int failed = 0;
    int alloc_count;
    logic [5:0] allocated_regs[$];  // Queue to track allocated registers
    logic [5:0] first_alloc;
    logic [5:0] second_alloc;
    logic is_not_rrt_reg;
    logic p0_allocated;

    // Helper task to check results
    task check_result(string test_name, logic expected, logic actual);
        if (expected === actual) begin
            $display("[PASS] %s", test_name);
            passed++;
        end else begin
            $display("[FAIL] %s: Expected %b, Got %b", test_name, expected, actual);
            failed++;
        end
    endtask

    // Helper task to reset the DUT
    task reset_dut();
        rst = 1;
        flush = 0;
        alloc_req <= 0;
        free_req = 0;
        free_reg = 0;
        for (int i = 0; i < 32; i++) begin
            rrt_in[i] = '0;
        end
        @(posedge clk);
        @(posedge clk);
        rst = 0;
    endtask

    // Main test sequence
    initial begin
        // Setup waveform dumping
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, "+all");
        
        $display("========================================");
        $display("Starting Freelist Testbench");
        $display("========================================\n");

        // Initialize signals
        rst = 0;
        flush = 0;
        alloc_req <= 0;
        free_req = 0;
        free_reg = 0;
        for (int i = 0; i < 32; i++) begin
            rrt_in[i] = '0;
        end

        //==================================================
        // TEST 1: Flush with RRT
        //==================================================
        test_num++;
        $display("Test %0d: Flush with RRT", test_num);
        reset_dut();
        
        // Setup RRT to indicate some registers are allocated
        for (int i = 0; i < 10; i++) begin
            rrt_in[i].valid = 1'b1;
            rrt_in[i].phys_reg = i[5:0] + 6'd10;  // P10-P19 are allocated
            rrt_in[i].ready = 1'b1;
        end
        
        // Trigger flush
        flush <= 1;
        @(posedge clk);
        flush <= 0;
        @(posedge clk);
        
        $display("  After flush, freelist rebuilt from RRT");
        
        // Check that P10-P19 are marked as allocated (not free)
        for (int i = 10; i < 20; i++) begin
            if (dut.free_list[i]) begin
                $display("  [ERROR] P%0d should be allocated but is marked free", i);
                failed++;
            end
        end
        check_result("P10-P19 marked as allocated", 1'b1, 
                     (dut.free_list[10] == 1'b0 && dut.free_list[15] == 1'b0 && dut.free_list[19] == 1'b0));
        
        // Check that registers outside P10-P19 are free (except P0)
        check_result("P1 is free", 1'b1, dut.free_list[1]);
        check_result("P25 is free", 1'b1, dut.free_list[25]);
        
        // Now allocate a register, it should be P1 (first free)
        alloc_req <= 1;
        @(posedge clk);
        $display("  Allocated register after flush: P%0d", alloc_reg);
        check_result("First allocation is P1", 1'b1, (alloc_reg == 6'd1));
        alloc_req <= 0;
        @(posedge clk);
        $display("");

        //==================================================
        // TEST 2: Flush with Full RRT
        //==================================================
        test_num++;
        $display("Test %0d: Flush with Full RRT (all arch regs mapped)", test_num);
        reset_dut();
        
        // Map all 32 architectural registers to different physical registers
        for (int i = 0; i < 32; i++) begin
            rrt_in[i].valid = 1'b1;
            rrt_in[i].phys_reg = i[5:0] + 6'd1;  // P1-P32 are allocated
            rrt_in[i].ready = 1'b1;
        end
        
        flush <= 1;
        @(posedge clk);
        flush <= 0;
        @(posedge clk);
        
        // After flush, P33 onwards should be free
        alloc_req <= 1;
        @(posedge clk);
        check_result("Allocated reg >= P33", 1'b1, (alloc_reg >= 6'd33));
        $display("  Allocated register: P%0d", alloc_reg);
        alloc_req <= 0;
        @(posedge clk);
        $display("");

        //==================================================
        // Final Report
        //==================================================
        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total Tests Run: %0d", test_num);
        $display("Checks Passed:   %0d", passed);
        $display("Checks Failed:   %0d", failed);
        $display("========================================");
        
        if (failed == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("SOME TESTS FAILED!");
        end
        $display("========================================\n");
        
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule
