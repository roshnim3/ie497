`timescale 1ns/1ps

module stack_tb;

    // Clock and reset
    logic clk;
    logic rst;
    
    // Stack parameters
    parameter DATA_WIDTH = 32;
    parameter STACK_SIZE = 8;  // Smaller for easier testing
    
    // Stack signals
    logic                    flush;
    logic                    push;
    logic                    pop;
    logic [DATA_WIDTH-1:0]   din;
    logic [DATA_WIDTH-1:0]   dout;
    logic                    full;
    logic                    empty;
    
    // Test tracking
    int test_num;
    int pass_count;
    int fail_count;
    
    // DUT instantiation
    stack #(
        .DATA_WIDTH(DATA_WIDTH),
        .STACK_SIZE(STACK_SIZE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .push(push),
        .pop(pop),
        .din(din),
        .dout(dout),
        .full(full),
        .empty(empty)
    );
    
    // Clock generation (10ns period = 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Waveform dumping
    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, stack_tb, "+all");
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
        flush = 0;
        push = 0;
        pop = 0;
        din = 32'h0;
        
        $display("\n========================================");
        $display("Stack (LIFO) Testbench");
        $display("Stack Size: %0d entries", STACK_SIZE);
        $display("========================================\n");
        
        // Reset
        repeat(3) @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        // Test 1: Initial state (should be empty)
        $display("\n--- Test 1: Initial State ---");
        check_result("Empty after reset", empty && !full);
        check_result("Output is zero when empty", dout == 32'h0);
        
        // Test 2: Single push and pop
        $display("\n--- Test 2: Single Push/Pop ---");
        push = 1;
        din = 32'hDEAD_BEEF;
        @(posedge clk);
        push = 0;
        @(posedge clk);
        check_result("Not empty after push", !empty);
        check_result("Correct data on top", dout == 32'hDEAD_BEEF);
        
        pop = 1;
        @(posedge clk);
        pop = 0;
        @(posedge clk);
        check_result("Empty after pop", empty);
        
        // Test 3: Multiple pushes (LIFO order)
        $display("\n--- Test 3: LIFO Order ---");
        push = 1;
        din = 32'h0000_0001;
        @(posedge clk);
        din = 32'h0000_0002;
        @(posedge clk);
        din = 32'h0000_0003;
        @(posedge clk);
        push = 0;
        @(posedge clk);
        
        check_result("Top is last pushed (3)", dout == 32'h0000_0003);
        
        pop = 1;
        @(posedge clk);
        check_result("After pop, top is 2", dout == 32'h0000_0002);
        @(posedge clk);
        check_result("After second pop, top is 1", dout == 32'h0000_0001);
        @(posedge clk);
        pop = 0;
        check_result("Empty after all pops", empty);
        
        // Test 4: Fill stack completely
        $display("\n--- Test 4: Fill Stack ---");
        push = 1;
        for (int i = 0; i < STACK_SIZE; i++) begin
            din = 32'h0000_0100 + i;
            @(posedge clk);
        end
        push = 0;
        @(posedge clk);
        
        check_result("Stack full after STACK_SIZE pushes", full);
        check_result("Top element correct when full", dout == 32'h0000_0100 + STACK_SIZE - 1);
        
        // Test 5: Push to full stack (should be ignored)
        $display("\n--- Test 5: Push to Full Stack ---");
        push = 1;
        din = 32'hBAD_BAD;
        @(posedge clk);
        push = 0;
        @(posedge clk);
        
        check_result("Push to full ignored", dout != 32'hBAD_BAD && full);
        
        // Test 6: Empty full stack
        $display("\n--- Test 6: Empty Full Stack ---");
        pop = 1;
        for (int i = 0; i < STACK_SIZE; i++) begin
            @(posedge clk);
        end
        pop = 0;
        @(posedge clk);
        
        check_result("Stack empty after all pops", empty);
        
        // Test 7: Pop from empty stack (should be ignored)
        $display("\n--- Test 7: Pop from Empty Stack ---");
        pop = 1;
        @(posedge clk);
        pop = 0;
        @(posedge clk);
        
        check_result("Still empty after pop on empty", empty);
        
        // Test 8: Simultaneous push and pop (empty stack)
        $display("\n--- Test 8: Simultaneous Push/Pop on Empty ---");
        push = 1;
        pop = 1;
        din = 32'h1111_1111;
        @(posedge clk);
        push = 0;
        pop = 0;
        @(posedge clk);
        
        check_result("Push takes precedence on empty", !empty && dout == 32'h1111_1111);
        
        // Test 9: Simultaneous push and pop (non-empty stack)
        $display("\n--- Test 9: Simultaneous Push/Pop on Non-Empty ---");
        // Stack has one element (0x1111_1111) from previous test
        push = 1;
        pop = 1;
        din = 32'h2222_2222;
        @(posedge clk);
        push = 0;
        pop = 0;
        @(posedge clk);
        
        check_result("Replace top element", !empty && dout == 32'h2222_2222);
        
        // Clear stack for flush test
        pop = 1;
        @(posedge clk);
        pop = 0;
        
        // Test 10: Flush
        $display("\n--- Test 10: Flush ---");
        push = 1;
        for (int i = 0; i < 4; i++) begin
            din = 32'hF000_0000 + i;
            @(posedge clk);
        end
        push = 0;
        @(posedge clk);
        
        check_result("Stack has elements before flush", !empty);
        
        flush = 1;
        @(posedge clk);
        flush = 0;
        @(posedge clk);
        
        check_result("Stack empty after flush", empty);
        
        // Test 11: Rapid push/pop sequence
        $display("\n--- Test 11: Rapid Push/Pop Sequence ---");
        push = 1;
        din = 32'hAAAA_AAAA;
        @(posedge clk);
        push = 0;
        pop = 1;
        @(posedge clk);
        pop = 0;
        push = 1;
        din = 32'hBBBB_BBBB;
        @(posedge clk);
        push = 0;
        @(posedge clk);
        
        check_result("Correct value after rapid sequence", dout == 32'hBBBB_BBBB);
        
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
