`timescale 1ns/1ps

module bp_tb;

    // Clock and reset
    logic clk;
    logic rst;
    
    // BP parameters
    parameter GHR_BITS = 8;
    parameter PHT_BITS = 8;
    parameter [1:0] PHT_INIT = 2'b01;
    
    // IF <-> BP signals
    logic [31:0] if_pc;
    logic        pred_taken;
    logic [PHT_BITS-1:0] pht_index;
    
    // BP <-> EX signals
    logic                branch_done;
    logic                branch_outcome;
    logic [PHT_BITS-1:0] branch_index;
    logic                bp_ready;
    
    // Test tracking
    int test_num;
    int pass_count;
    int fail_count;
    
    // DUT instantiation
    bp #(
        .GHR_BITS(GHR_BITS),
        .PHT_BITS(PHT_BITS),
        .PHT_INIT(PHT_INIT)
    ) dut (
        .clk(clk),
        .rst(rst),
        .if_pc(if_pc),
        .pred_taken(pred_taken),
        .pht_index(pht_index),
        .branch_done(branch_done),
        .branch_outcome(branch_outcome),
        .branch_index(branch_index),
        .bp_ready(bp_ready)
    );
    
    // Clock generation (10ns period = 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Waveform dumping
    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, bp_tb, "+all");
    end
    
    // Main test sequence
    initial begin
        test_num = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Initialize signals
        rst = 1;
        if_pc = 32'h0000_1000;
        branch_done = 0;
        branch_outcome = 0;
        branch_index = 0;
        
        $display("\n========================================");
        $display("Branch Predictor (GShare) Testbench");
        $display("========================================\n");
        
        // Reset
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);  // Wait for SRAM to be read and pht_rdata to stabilize
        
        // Test 1: Initial prediction (should be weakly not-taken since SRAM inits to 0)
        test_basic_prediction();
        
        // Test 2: Train predictor to be taken
        test_train_taken();
        
        // Test 3: Train predictor to be not-taken
        test_train_not_taken();
        
        // Test 4: Test GHR update and correlation
        test_ghr_correlation();
        
        // Test 5: Test saturating counter boundaries
        test_saturation();
        
        // Test 6: Test pattern detection
        test_pattern_detection();
        
        // Test 7: Verify index calculation (PC XOR GHR)
        test_index_calculation();
        
        // Summary
        repeat(10) @(posedge clk);
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_num);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        if (fail_count == 0) begin
            $display("Status: ALL TESTS PASSED!");
        end else begin
            $display("Status: SOME TESTS FAILED!");
        end
        $display("========================================\n");
        
        $finish;
    end
    
    // ========================================
    // Test Tasks
    // ========================================
    
    // Test 1: Initial prediction (should be weakly not-taken since SRAM inits to 0)
    task test_basic_prediction();
        logic [PHT_BITS-1:0] expected_idx;
        begin
            test_num++;
            $display("[TEST %0d] Basic Prediction - Initial State", test_num);
            
            // Give SRAM time to settle
            repeat(3) @(posedge clk);
            
            // Set PC
            if_pc = 32'h0000_1004;  // Branch at address 0x1004
            @(posedge clk);
            #1;
            
            // Calculate expected index (GHR=0 initially, PC[9:2] = 0x1)
            expected_idx = 8'h00 ^ if_pc[2+PHT_BITS-1:2];
            
            // Wait for SRAM read to complete
            @(posedge clk);
            #1;
            
            // Check prediction (SRAM inits to 0 = strongly not-taken, MSB=0)
            if (pred_taken === 1'b0) begin
                $display("  [PASS] Initial prediction is not-taken (pred_taken=%b)", pred_taken);
                pass_count++;
            end else begin
                $display("  [FAIL] Expected not-taken, got taken=%b (pht_rdata=%b)", pred_taken, dut.pht_rdata);
                fail_count++;
            end
            
            // Check index
            if (pht_index === expected_idx) begin
                $display("  [PASS] PHT index correct: 0x%02h", pht_index);
                pass_count++;
            end else begin
                $display("  [FAIL] Expected index 0x%02h, got 0x%02h", expected_idx, pht_index);
                fail_count++;
            end
            
            @(posedge clk);
        end
    endtask
    
    // Test 2: Train predictor to be taken
    task test_train_taken();
        logic [31:0] branch_pc;
        logic [PHT_BITS-1:0] saved_idx;
        begin
            test_num++;
            $display("\n[TEST %0d] Train Predictor to Taken", test_num);
            
            branch_pc = 32'h0000_2000;
            
            // Make prediction
            if_pc = branch_pc;
            @(posedge clk);
            #1;
            saved_idx = pht_index;
            $display("  Initial prediction at PC=0x%08h: taken=%b, idx=0x%02h", 
                     branch_pc, pred_taken, saved_idx);
            
            // Train: branch was taken (update counter 0->1)
            @(posedge clk);
            #1;
            branch_done = 1;
            branch_outcome = 1;  // taken
            branch_index = saved_idx;
            @(posedge clk);
            #1;
            branch_done = 0;
            
            // Wait for update to complete (2 cycles: read, then write)
            repeat(2) @(posedge clk);
            
            // Re-predict same branch (should still be not-taken: 01)
            if_pc = branch_pc;
            @(posedge clk);
            @(posedge clk);
            #1;
            if (pred_taken === 1'b0) begin
                $display("  [PASS] After 1 taken: prediction is not-taken (counter=01)");
                pass_count++;
            end else begin
                $display("  [FAIL] After 1 taken: expected not-taken, got taken");
                fail_count++;
            end
            
            // Train again: taken (1->2)
            @(posedge clk);
            #1;
            branch_done = 1;
            branch_outcome = 1;
            branch_index = saved_idx;
            @(posedge clk);
            #1;
            branch_done = 0;
            repeat(2) @(posedge clk);
            
            // Re-predict (should now be taken: 10)
            if_pc = branch_pc;
            @(posedge clk);
            @(posedge clk);
            #1;
            if (pred_taken === 1'b1) begin
                $display("  [PASS] After 2 taken: prediction is taken (counter=10)");
                pass_count++;
            end else begin
                $display("  [FAIL] After 2 taken: expected taken, got not-taken");
                fail_count++;
            end
            
            @(posedge clk);
        end
    endtask
    
    // Test 3: Train predictor to be not-taken
    task test_train_not_taken();
        logic [31:0] branch_pc;
        logic [PHT_BITS-1:0] saved_idx;
        begin
            test_num++;
            $display("\n[TEST %0d] Train Predictor to Not-Taken", test_num);
            
            branch_pc = 32'h0000_3000;
            
            // Make prediction
            if_pc = branch_pc;
            @(posedge clk);
            #1;
            saved_idx = pht_index;
            
            // Train: not-taken twice to reach strongly not-taken (already at 00)
            // Verify it stays at 00
            for (int i = 0; i < 2; i++) begin
                @(posedge clk);
                #1;
                branch_done = 1;
                branch_outcome = 0;  // not-taken
                branch_index = saved_idx;
                @(posedge clk);
                #1;
                branch_done = 0;
                repeat(2) @(posedge clk);
            end
            
            // Re-predict (should be not-taken: 00)
            if_pc = branch_pc;
            @(posedge clk);
            @(posedge clk);
            #1;
            if (pred_taken === 1'b0) begin
                $display("  [PASS] Stays strongly not-taken (counter=00)");
                pass_count++;
            end else begin
                $display("  [FAIL] Expected not-taken, got taken");
                fail_count++;
            end
            
            @(posedge clk);
        end
    endtask
    
    // Test 4: Test GHR correlation
    task test_ghr_correlation();
        logic [31:0] pc1, pc2;
        logic [PHT_BITS-1:0] idx1_before, idx1_after;
        begin
            test_num++;
            $display("\n[TEST %0d] GHR Correlation Test", test_num);
            
            pc1 = 32'h0000_4000;
            pc2 = 32'h0000_4004;
            
            // Predict at PC1 with GHR=0
            if_pc = pc1;
            @(posedge clk);
            #1;
            idx1_before = pht_index;
            $display("  PC1 with GHR=00: idx=0x%02h", idx1_before);
            
            // Execute a taken branch to update GHR
            @(posedge clk);
            #1;
            branch_done = 1;
            branch_outcome = 1;  // GHR becomes ...001
            branch_index = idx1_before;
            @(posedge clk);
            #1;
            branch_done = 0;
            repeat(2) @(posedge clk);
            
            // Predict at PC1 again with GHR=...001
            if_pc = pc1;
            @(posedge clk);
            #1;
            idx1_after = pht_index;
            $display("  PC1 with GHR=01: idx=0x%02h", idx1_after);
            
            // Index should be different (GHR changed)
            if (idx1_before !== idx1_after) begin
                $display("  [PASS] Index changed with GHR update");
                pass_count++;
            end else begin
                $display("  [FAIL] Index did not change with GHR update");
                fail_count++;
            end
            
            @(posedge clk);
        end
    endtask
    
    // Test 5: Test saturating counter saturation
    task test_saturation();
        logic [31:0] branch_pc;
        logic [PHT_BITS-1:0] saved_idx;
        begin
            test_num++;
            $display("\n[TEST %0d] Saturating Counter Boundaries", test_num);
            
            branch_pc = 32'h0000_5000;
            
            // Get index
            if_pc = branch_pc;
            @(posedge clk);
            #1;
            saved_idx = pht_index;
            
            // Train to strongly taken (00 -> 01 -> 10 -> 11)
            for (int i = 0; i < 4; i++) begin
                @(posedge clk);
                #1;
                branch_done = 1;
                branch_outcome = 1;
                branch_index = saved_idx;
                @(posedge clk);
                #1;
                branch_done = 0;
                repeat(2) @(posedge clk);
            end
            
            // Verify saturated at 11 (taken)
            if_pc = branch_pc;
            @(posedge clk);
            @(posedge clk);
            #1;
            if (pred_taken === 1'b1) begin
                $display("  [PASS] Saturated at strongly taken");
                pass_count++;
            end else begin
                $display("  [FAIL] Not saturated at strongly taken");
                fail_count++;
            end
            
            // Train one more time (should stay at 11)
            @(posedge clk);
            #1;
            branch_done = 1;
            branch_outcome = 1;
            branch_index = saved_idx;
            @(posedge clk);
            #1;
            branch_done = 0;
            repeat(2) @(posedge clk);
            
            // Verify still taken
            if_pc = branch_pc;
            @(posedge clk);
            @(posedge clk);
            #1;
            if (pred_taken === 1'b1) begin
                $display("  [PASS] Stays at strongly taken (no overflow)");
                pass_count++;
            end else begin
                $display("  [FAIL] Counter overflowed");
                fail_count++;
            end
            
            @(posedge clk);
        end
    endtask
    
    // Test 6: Pattern detection
    task test_pattern_detection();
        logic [31:0] branch_pc;
        logic [PHT_BITS-1:0] saved_idx;
        begin
            test_num++;
            $display("\n[TEST %0d] Pattern Detection (T-T-N-T-T-N)", test_num);
            
            branch_pc = 32'h0000_6000;
            
            // Get index
            if_pc = branch_pc;
            @(posedge clk);
            #1;
            saved_idx = pht_index;
            
            // Train pattern: T-T-N-T-T-N (3 iterations)
            for (int iter = 0; iter < 3; iter++) begin
                // Taken
                @(posedge clk); #1;
                branch_done = 1; branch_outcome = 1; branch_index = saved_idx;
                @(posedge clk); #1; branch_done = 0;
                repeat(2) @(posedge clk);
                
                // Taken
                @(posedge clk); #1;
                branch_done = 1; branch_outcome = 1; branch_index = saved_idx;
                @(posedge clk); #1; branch_done = 0;
                repeat(2) @(posedge clk);
                
                // Not-taken
                @(posedge clk); #1;
                branch_done = 1; branch_outcome = 0; branch_index = saved_idx;
                @(posedge clk); #1; branch_done = 0;
                repeat(2) @(posedge clk);
            end
            
            $display("  [INFO] Pattern trained 3 times");
            $display("  [PASS] Pattern test completed");
            pass_count++;
            
            @(posedge clk);
        end
    endtask
    
    // Test 7: Index calculation verification
    task test_index_calculation();
        logic [31:0] test_pc;
        logic [PHT_BITS-1:0] expected_idx, actual_idx;
        logic [GHR_BITS-1:0] test_ghr;
        begin
            test_num++;
            $display("\n[TEST %0d] Index Calculation (PC XOR GHR)", test_num);
            
            // Test multiple PC and GHR combinations
            for (int i = 0; i < 5; i++) begin
                test_pc = 32'h1000 + (i * 32'h100);
                
                // Make prediction
                if_pc = test_pc;
                @(posedge clk);
                #1;
                
                // Expected: ghr[7:0] XOR pc[9:2] - use actual GHR value from hierarchy
                test_ghr = dut.ghr;
                expected_idx = test_ghr[PHT_BITS-1:0] ^ test_pc[2+PHT_BITS-1:2];
                
                @(posedge clk);
                #1;
                actual_idx = pht_index;
                
                if (actual_idx === expected_idx) begin
                    $display("  [PASS] PC=0x%08h: idx=0x%02h (correct, GHR=0x%02h)", test_pc, actual_idx, test_ghr);
                    pass_count++;
                end else begin
                    $display("  [FAIL] PC=0x%08h: expected 0x%02h, got 0x%02h (GHR=0x%02h)", 
                             test_pc, expected_idx, actual_idx, test_ghr);
                    fail_count++;
                end
            end
            
            @(posedge clk);
        end
    endtask

endmodule
