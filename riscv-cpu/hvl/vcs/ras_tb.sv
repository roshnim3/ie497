`timescale 1ns/1ps

module ras_tb
import ooo_types::*;
();

    // Clock and reset
    logic clk;
    logic rst;
    
    // RAS parameters
    parameter RAS_SIZE = 8;  // Smaller for easier testing
    
    // RAS signals
    logic           is_call;
    logic           is_return;
    logic [31:0]    decode_pc;
    logic           br_mispredict;
    logic [31:0]    ras_target;
    logic           ras_valid;
    
    // Test tracking
    int test_num;
    int pass_count;
    int fail_count;
    
    // DUT instantiation
    ras #(
        .RAS_SIZE(RAS_SIZE)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .is_call        (is_call),
        .is_return      (is_return),
        .decode_pc      (decode_pc),
        .br_mispredict  (br_mispredict),
        .ras_target     (ras_target),
        .ras_valid      (ras_valid)
    );
    
    // Clock generation (10ns period = 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Waveform dumping
    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, ras_tb, "+all");
    end
    
    // Test result checking
    task check_result(string test_name, logic condition);
        test_num++;
        if (condition) begin
            $display("[TEST %0d] %s [PASS]", test_num, test_name);
            pass_count++;
        end else begin
            $display("[TEST %0d] %s [FAIL]", test_num, test_name);
            fail_count++;
        end
    endtask
    
    // Main test sequence
    initial begin
        test_num = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Initialize signals
        rst = 1;
        is_call = 0;
        is_return = 0;
        decode_pc = 32'h0;
        br_mispredict = 0;
        
        $display("\n========================================");
        $display("Return Address Stack (RAS) Testbench");
        $display("RAS Size: %0d entries", RAS_SIZE);
        $display("========================================\n");
        
        // Reset
        repeat(3) @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        // Test 1: Initial state (no valid prediction)
        $display("\n--- Test 1: Initial State ---");
        check_result("No valid prediction after reset", !ras_valid);
        
        // Test 2: Single call and return
        $display("\n--- Test 2: Single Call/Return ---");
        is_call = 1;
        decode_pc = 32'h1000_0000;  // PC of call instruction
        @(posedge clk);
        is_call = 0;
        @(posedge clk);
        
        check_result("Valid prediction after call", ras_valid);
        check_result("Correct return address (PC+4)", ras_target == 32'h1000_0004);
        
        is_return = 1;
        @(posedge clk);
        is_return = 0;
        @(posedge clk);
        
        check_result("No valid prediction after return", !ras_valid);
        
        // Test 3: Nested calls (push multiple addresses)
        $display("\n--- Test 3: Nested Calls ---");
        is_call = 1;
        decode_pc = 32'h2000_0000;  // First call
        @(posedge clk);
        decode_pc = 32'h3000_0000;  // Second call (nested)
        @(posedge clk);
        decode_pc = 32'h4000_0000;  // Third call (nested)
        @(posedge clk);
        is_call = 0;
        @(posedge clk);
        
        check_result("Prediction is last return address", ras_target == 32'h4000_0004);
        
        // Pop in LIFO order
        is_return = 1;
        @(posedge clk);
        check_result("After first return, addr is second nested", ras_target == 32'h3000_0004);
        @(posedge clk);
        check_result("After second return, addr is first nested", ras_target == 32'h2000_0004);
        @(posedge clk);
        is_return = 0;
        check_result("After all returns, no valid prediction", !ras_valid);
        
        // Test 4: Fill RAS completely
        $display("\n--- Test 4: Fill RAS ---");
        is_call = 1;
        for (int i = 0; i < RAS_SIZE; i++) begin
            decode_pc = 32'h5000_0000 + (i << 2);
            @(posedge clk);
        end
        is_call = 0;
        @(posedge clk);
        
        check_result("Top address when full", ras_target == (32'h5000_0000 + ((RAS_SIZE-1) << 2) + 4));
        
        // Test 5: Push to full RAS (should wrap/ignore)
        $display("\n--- Test 5: Call to Full RAS ---");
        is_call = 1;
        decode_pc = 32'hBAD_0000;
        @(posedge clk);
        is_call = 0;
        @(posedge clk);
        
        check_result("Call to full RAS ignored", ras_target != 32'hBAD_0004);
        
        // Test 6: Pop all entries
        $display("\n--- Test 6: Empty Full RAS ---");
        is_return = 1;
        for (int i = 0; i < RAS_SIZE; i++) begin
            @(posedge clk);
        end
        is_return = 0;
        @(posedge clk);
        
        check_result("No prediction after emptying", !ras_valid);
        
        // Test 7: Recovery (mispredict flush)
        $display("\n--- Test 7: Recovery on Mispredict ---");
        // Push some addresses
        is_call = 1;
        decode_pc = 32'h6000_0000;
        @(posedge clk);
        decode_pc = 32'h7000_0000;
        @(posedge clk);
        is_call = 0;
        @(posedge clk);
        
        check_result("RAS has entries before recovery", ras_valid);
        
        // Trigger recovery (mispredict)
        br_mispredict = 1;
        @(posedge clk);
        br_mispredict = 0;
        @(posedge clk);
        
        check_result("RAS flushed after recovery", !ras_valid);
        
        // Test 8: Call/return pattern with recovery
        $display("\n--- Test 8: Recovery During Speculation ---");
        is_call = 1;
        decode_pc = 32'h8000_0000;
        @(posedge clk);
        decode_pc = 32'h9000_0000;
        @(posedge clk);
        decode_pc = 32'hA000_0000;
        @(posedge clk);
        is_call = 0;
        @(posedge clk);
        
        // Mispredict in the middle
        br_mispredict = 1;
        @(posedge clk);
        br_mispredict = 0;
        @(posedge clk);
        
        check_result("Stack cleared on speculative mispredict", !ras_valid);
        
        // Test 9: Simultaneous call and return (tail call optimization scenario)
        $display("\n--- Test 9: Simultaneous Call/Return ---");
        is_call = 1;
        decode_pc = 32'hB000_0000;
        @(posedge clk);
        is_call = 0;
        @(posedge clk);
        
        // Simultaneous call and return (e.g., tail call)
        is_call = 1;
        is_return = 1;
        decode_pc = 32'hC000_0000;
        @(posedge clk);
        is_call = 0;
        is_return = 0;
        @(posedge clk);
        
        check_result("Simultaneous call/return replaces top", ras_target == 32'hC000_0004);
        
        // Final summary
        @(posedge clk);
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_num);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        if (fail_count == 0) begin
            $display("\nAll tests PASSED! ✓");
        end else begin
            $display("\nSome tests FAILED! ✗");
        end
        $display("========================================\n");
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #10000;
        $display("\nERROR: Testbench timeout!");
        $finish;
    end

endmodule
