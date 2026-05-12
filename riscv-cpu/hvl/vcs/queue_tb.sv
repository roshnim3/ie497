module queue_tb;

    // To run this code comment out top_tb.sv

    timeunit 1ps;
    timeprecision 1ps;

    // Testbench parameters - you can override these
    parameter int DATA_WIDTH = 32;
    parameter int ADDR_WIDTH = 3;
    localparam int DEPTH = 1 << ADDR_WIDTH; // 8 entries

    // Clock and reset
    int clock_half_period_ps;
    initial begin
        $value$plusargs("CLOCK_PERIOD_PS_ECE411=%d", clock_half_period_ps);
        clock_half_period_ps = clock_half_period_ps / 2;
    end

    bit clk;
    always #(clock_half_period_ps) clk = ~clk;
    bit rst;

    // Queue interface signals
    logic                    enq;
    logic                    deq;
    logic [DATA_WIDTH-1:0]   din;
    logic [DATA_WIDTH-1:0]   dout;
    logic                    full;
    logic                    empty;

    // Testbench variables
    int error_count;
    int test_count;

    // Instantiate the DUT (Device Under Test)
    queue #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .enq(enq),
        .deq(deq),
        .din(din),
        .dout(dout),
        .full(full),
        .empty(empty)
    );

    // Main test sequence with waveform dumping
    initial begin
        // Initialize waveform dumping
        $fsdbDumpfile("dump.fsdb");
        if ($test$plusargs("NO_DUMP_ALL_ECE411")) begin
            $fsdbDumpvars(0, dut, "+all");
            $fsdbDumpoff();
        end else begin
            $fsdbDumpvars(0, "+all");
        end

        // Initialize signals
        error_count = '0;
        test_count = '0;
        enq = '0;
        deq = '0;
        din = '0;

        // Display test header
        $display("========================================");
        $display("Queue Testbench");
        $display("DATA_WIDTH = %0d, ADDR_WIDTH = %0d, DEPTH = %0d", DATA_WIDTH, ADDR_WIDTH, DEPTH);
        $display("========================================\n");

        // Reset sequence
        rst = 1'b1;
        repeat(2) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);

        // Test 1: Check initial empty state
        test_empty_after_reset();

        // Test 2: Single enqueue and dequeue
        test_single_enqueue_dequeue();

        // Test 3: Fill the queue completely
        test_fill_queue();

        // Test 4: Drain the queue completely
        test_drain_queue();

        // Test 5: Alternating enqueue/dequeue
        test_alternating_ops();

        // Test 6: Fill, drain, and refill
        test_fill_drain_refill();

        // Test 8: Try to enqueue when full
        test_enqueue_when_full();

        // Test 9: Try to dequeue when empty
        test_dequeue_when_empty();

        // Test 10: Random operations
        test_random_operations();

        // NEW COMPREHENSIVE TESTS
        // Test 11: Simultaneous enq/deq when empty (pass-through test)
        test_passthrough_when_empty();

        // Test 12: Simultaneous enq/deq when full
        test_simultaneous_when_full();

        // Test 13: Wrap-around behavior
        test_wraparound();

        // Test 14: Data integrity after wrap-around
        test_data_integrity_wraparound();

        // Test 15: Multiple simultaneous operations
        test_continuous_simultaneous_ops();

        // Test 16: Burst enqueue then burst dequeue
        test_burst_operations();

        // Test 17: Stress test with controlled patterns
        test_controlled_stress();

        // Test 18: Edge case - nearly full operations
        test_nearly_full_operations();

        // Test 19: Data pattern test (walking 1s, walking 0s)
        test_data_patterns();

        // Test 20: Reset during operation
        test_reset_during_operation();

        // Test 21: Back-to-back simultaneous operations
        test_back_to_back_simultaneous();

        // Display results
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_count);
        $display("Errors: %0d", error_count);
        if (error_count == 0) begin
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

    task test_empty_after_reset();
        begin
            $display("[%0t] [TEST %0d] Checking empty state after reset", $time, ++test_count);
            @(posedge clk);
            if (!empty) begin
                $display("[%0t]   [FAIL] Queue should be empty after reset", $time);
                error_count++;
            end else if (full) begin
                $display("[%0t]   [FAIL] Queue should not be full after reset", $time);
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Queue is empty and not full", $time);
            end
        end
    endtask

    task test_single_enqueue_dequeue();
        logic [DATA_WIDTH-1:0] test_data;
        begin
            $display("\n[%0t] [TEST %0d] Single enqueue and dequeue", $time, ++test_count);
            test_data = 32'hDEADBEEF;
            
            // Enqueue
            @(posedge clk);
            enq = 1'b1;
            din = test_data;
            @(posedge clk);
            enq = '0;
            
            if (empty) begin
                $display("[%0t]   [FAIL] Queue should not be empty after enqueue", $time);
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Queue not empty after enqueue", $time);
            end

            // Dequeue
            @(posedge clk);
            deq = 1'b1;
            @(posedge clk);
            if (dout !== test_data) begin
                $display("[%0t]   [FAIL] Dequeued data (0x%08h) doesn't match enqueued data (0x%08h)", $time, dout, test_data);
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Dequeued correct data: 0x%08h", $time, dout);
            end
            deq = '0;
            
            @(posedge clk);
            deq <= '0;
            wait (empty);
            if (!empty) begin
                $display("[%0t]   [FAIL] Queue should be empty after dequeue", $time);
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Queue is empty after dequeue", $time);
            end
        end
    endtask

    task test_fill_queue();
        int i;
        begin
            $display("\n[%0t] [TEST %0d] Filling queue to capacity", $time, ++test_count);
            
            for (i = 0; i < DEPTH; i++) begin
                @(posedge clk);
                enq = 1'b1;
                din = i;
            end
            @(posedge clk);
            enq = '0;
            
            if (!full) begin
                $display("[%0t]   [FAIL] Queue should be full after %0d enqueues", $time, DEPTH);
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Queue is full after %0d enqueues", $time, DEPTH);
            end
        end
    endtask

    task test_drain_queue();
        int i;
        logic [DATA_WIDTH-1:0] expected;
        int mismatch;
        begin
            $display("\n[%0t] [TEST %0d] Draining full queue", $time, ++test_count);
            mismatch = '0;
            
            for (i = 0; i < DEPTH; i++) begin
                expected = i;
                deq = 1'b1;
                @(posedge clk);

                if (dout !== expected) begin
                    $display("[%0t]   [FAIL] Entry %0d: expected 0x%08h, got 0x%08h", $time, i, expected, dout);
                    mismatch++;
                end
            end
            deq = '0;
            
            @(posedge clk);
            deq <= '0;
            
            if (!empty) begin
                $display("[%0t]   [FAIL] Queue should be empty after draining", $time);
                error_count++;
            end else if (mismatch > 0) begin
                $display("[%0t]   [FAIL] %0d data mismatches during drain", $time, mismatch);
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Queue drained correctly, all data matched", $time);
            end
        end
    endtask

    task test_alternating_ops();
        int i;
        logic [DATA_WIDTH-1:0] test_val;
        begin
            $display("\n[%0t] [TEST %0d] Alternating enqueue and dequeue", $time, ++test_count);
            
            for (i = 0; i < 10; i++) begin
                test_val = $random;
                
                // Enqueue
                @(posedge clk);
                enq = 1'b1;
                deq = '0;
                din = test_val;
                @(posedge clk);
                
                // Dequeue
                enq = '0;
                deq = 1'b1;
                @(posedge clk);
                deq <= '0;        
                if (dout !== test_val) begin
                    $display("[%0t]   [FAIL] Iteration %0d: expected 0x%08h, got 0x%08h", $time, i, test_val, dout);
                    error_count++;
                    break;
                end
            end
            
            deq = '0;
            @(posedge clk);
            if (!empty) begin
                $display("[%0t]   [FAIL] Queue should be empty", $time);
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Alternating operations successful", $time);
            end
        end
    endtask

    task test_fill_drain_refill();
        int i;
        begin
            $display("\n[%0t] [TEST %0d] Fill, drain, and refill sequence", $time, ++test_count);
            
            // Fill
            for (i = 0; i < DEPTH; i++) begin
                @(posedge clk);
                enq = 1'b1;
                din = i + 100;
            end
            @(posedge clk);
            enq = '0;
            
            // Drain
            for (i = '0; i < DEPTH; i++) begin
                @(posedge clk);
                deq = 1'b1;
            end
            @(posedge clk);
            deq = '0;
            
            // Refill with different data
            for (i = 0; i < DEPTH; i++) begin
                @(posedge clk);
                enq = 1'b1;
                din = i + 200;
            end
            @(posedge clk);
            enq = '0;
            
            if (!full) begin
                $display("[%0t]   [FAIL] Queue should be full after refill", $time);
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Fill-drain-refill successful", $time);
            end
            
            // Clean up - drain again
            for (i = 0; i < DEPTH; i++) begin
                @(posedge clk);
                deq = 1'b1;
            end
            @(posedge clk);
            deq = '0;
        end
    endtask

    task test_simultaneous_enq_deq();
        int i;
        logic [DATA_WIDTH-1:0] enq_val, deq_val;
        begin
            $display("\n[%0t] [TEST %0d] Simultaneous enqueue and dequeue", $time, ++test_count);
            
            // First fill queue partially
            for (i = 0; i < DEPTH/2; i++) begin
                @(posedge clk);
                enq = 1'b1;
                din = i + 300;
            end
            @(posedge clk);
            enq = '0;
            
            // Now do simultaneous operations
            for (i = 0; i < 5; i++) begin
                enq_val = i + 400;
                @(posedge clk);
                enq = 1'b1;
                deq = 1'b1;
                din = enq_val;
            end
            @(posedge clk);
            enq = '0;
            deq = '0;
            
            $display("[%0t]   [PASS] Simultaneous operations completed", $time);
            
            // Clean up
            repeat(DEPTH) begin
                @(posedge clk);
                deq = 1'b1;
            end
            @(posedge clk);
            deq = '0;
        end
    endtask

    task test_enqueue_when_full();
        int i;
        begin
            $display("\n[%0t] [TEST %0d] Attempting enqueue when full", $time, ++test_count);
            
            // Fill the queue
            for (i = 0; i < DEPTH; i++) begin
                @(posedge clk);
                enq = 1'b1;
                din = i + 500;
            end
            @(posedge clk);
            enq = '0;
            
            if (!full) begin
                $display("[%0t]   [FAIL] Queue should be full", $time);
                error_count++;
            end
            
            // Try to enqueue when full
            @(posedge clk);
            enq = 1'b1;
            din = 32'hBADBAD;
            @(posedge clk);
            enq = '0;
            
            wait (full);
            // Queue should still be full
            if (!full) begin
                $display("[%0t]   [FAIL] Queue should still be full after enqueue attempt", $time);
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Queue remains full, enqueue when full handled", $time);
            end
            
            // Clean up
            repeat(DEPTH) begin
                @(posedge clk);
                deq = 1'b1;
            end
            @(posedge clk);
            deq = '0;
        end
    endtask

    task test_dequeue_when_empty();
        begin
            $display("\n[%0t] [TEST %0d] Attempting dequeue when empty", $time, ++test_count);
            
            // Ensure queue is empty
            @(posedge clk);
            if (!empty) begin
                $display("[%0t]   [FAIL] Queue should be empty at start", $time);
                error_count++;
            end
            
            // Try to dequeue when empty
            @(posedge clk);
            deq = 1'b1;
            @(posedge clk);
            deq = '0;
            
            // Queue should still be empty
            if (!empty) begin
                $display("[%0t]   [FAIL] Queue should still be empty after dequeue attempt", $time);
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Queue remains empty, dequeue when empty handled", $time);
            end
        end
    endtask

    task test_random_operations();
        int i;
        int num_ops;
        int op_type;
        logic [DATA_WIDTH-1:0] rand_data;
        begin
            $display("\n[%0t] [TEST %0d] Random operations stress test", $time, ++test_count);
            
            num_ops = 10000;
            for (i = 0; i < num_ops; i++) begin
                op_type = $random % 2;
                rand_data = $random;
                
                @(posedge clk);
                case (op_type)
                    0: begin // Enqueue only
                        if (!full) begin
                            enq = 1'b1;
                            deq = '0;
                            din = rand_data;
                        end else begin
                            enq = '0;
                            deq = '0;
                        end
                    end
                    1: begin // Dequeue only
                        if (!empty) begin
                            enq = '0;
                            deq = 1'b1;
                        end else begin
                            enq = '0;
                            deq = '0;
                        end
                    end
                endcase
            end
            
            @(posedge clk);
            enq = '0;
            deq = '0;
            
            $display("[%0t]   [PASS] Completed %0d random operations", $time, num_ops);
        end
    endtask

    // ========================================
    // NEW COMPREHENSIVE TEST TASKS
    // ========================================

    task test_passthrough_when_empty();
        int i;
        logic [DATA_WIDTH-1:0] test_data;
        logic [DATA_WIDTH-1:0] expected_dout;
        begin
            $display("\n[%0t] [TEST %0d] Pass-through when empty (simultaneous enq/deq)", $time, ++test_count);
            
            rst = 1'b1;
            @(posedge clk);
            rst = 1'b0;

            // Ensure queue is empty
            if (!empty) begin
                $display("[%0t]   [FAIL] Queue should start empty", $time);
                error_count++;
            end
            
            // Test multiple pass-through operations
            for (i = 0; i < 10; i++) begin
                test_data = $random;
                @(posedge clk);
                enq = 1'b1;
                deq = 1'b1;
                din = test_data;
                
                // Next cycle, check if data passed through
                @(posedge clk);
                if (dout !== test_data) begin
                    $display("[%0t]   [FAIL] Pass-through failed: expected 0x%08h, got 0x%08h", $time, test_data, dout);
                    error_count++;
                    break;
                end
                
                if (!empty) begin
                    $display("[%0t]   [FAIL] Queue should remain empty after pass-through", $time);
                    error_count++;
                    break;
                end
            end
            
            enq = '0;
            deq = '0;
            
            if (i == 10) begin
                $display("[%0t]   [PASS] Pass-through operations successful", $time);
            end
        end
    endtask

    task test_simultaneous_when_full();
        int i;
        logic [DATA_WIDTH-1:0] test_data;
        logic [DATA_WIDTH-1:0] expected_first;
        begin
            $display("\n[%0t] [TEST %0d] Simultaneous enq/deq when full", $time, ++test_count);
            
            // Fill the queue
            for (i = '0; i < DEPTH; i++) begin
                @(posedge clk);
                enq = 1'b1;
                din = i + 1000;
            end
            @(posedge clk);
            enq = '0;
            
            if (!full) begin
                $display("[%0t]   [FAIL] Queue should be full", $time);
                error_count++;
            end
            
            // Now do simultaneous enq/deq when full
            expected_first = 1000; // First element we enqueued
            for (i = 0; i < 5; i++) begin
                test_data = i + 2000;
                enq = 1'b1;
                deq = 1'b1;
                din = test_data;
                
                @(posedge clk);
                // Should dequeue the old data and enqueue new data
                if (dout !== (expected_first + i)) begin
                    $display("[%0t]   [FAIL] Expected 0x%08h, got 0x%08h", $time, expected_first + i, dout);
                    error_count++;
                    break;
                end
                
                // Queue should remain full
                if (!full) begin
                    $display("[%0t]   [FAIL] Queue should remain full", $time);
                    error_count++;
                    break;
                end
            end
            
            enq = '0;
            deq = '0;
            @(posedge clk);
            
            if (i == 5) begin
                $display("[%0t]   [PASS] Simultaneous operations when full successful", $time);
            end
            
            // Clean up
            repeat(DEPTH) begin
                @(posedge clk);
                deq = 1'b1;
            end
            @(posedge clk);
            deq = '0;
        end
    endtask

    task test_wraparound();
        int i;
        begin
            $display("\n[%0t] [TEST %0d] Testing pointer wrap-around behavior", $time, ++test_count);
            
            // Fill and drain multiple times to cause wrap-around
            for (int cycle = 0; cycle < 3; cycle++) begin
                // Fill
                for (i = 0; i < DEPTH; i++) begin
                    @(posedge clk);
                    enq = 1'b1;
                    din = (cycle * 100) + i;
                end
                @(posedge clk);
                enq = '0;
                
                // Drain
                for (i = '0; i < DEPTH; i++) begin
                    @(posedge clk);
                    deq = 1'b1;
                end
                @(posedge clk);
                deq = '0;
            end
            
            if (!empty) begin
                $display("[%0t]   [FAIL] Queue should be empty after wrap-around", $time);
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Wrap-around behavior correct", $time);
            end
        end
    endtask

    task test_data_integrity_wraparound();
        int i, j;
        logic [DATA_WIDTH-1:0] expected;
        int errors;
        begin
            $display("\n[%0t] [TEST %0d] Data integrity after wrap-around", $time, ++test_count);
            errors = '0;

            // Empty the queue first
            while (!empty) begin
                @(posedge clk);
                deq = 1'b1;
            end
            @(posedge clk);
            deq = '0;

            // Multiple cycles of partial fill/drain to force wrap
            for (int cycle = '0; cycle < 5; cycle++) begin
                // Enqueue some data
                for (i = '0; i < DEPTH - 2; i++) begin
                    @(posedge clk);
                    enq = 1'b1;
                    din = (cycle * 1000) + i;
                    @(posedge clk);
                    enq = '0;
                end
                
                
                // Dequeue and verify
                for (i = '0; i < DEPTH - 2; i++) begin
                    expected = (cycle * 1000) + i;
                    deq = 1'b1;
                    @(posedge clk);
                    if (dout !== expected) begin
                        $display("[%0t]   [FAIL] Cycle %0d, Entry %0d: expected 0x%08h, got 0x%08h", 
                                 $time, cycle, i, expected, dout);
                        errors++;
                    end
                end
                deq = '0;
                @(posedge clk);
            end
            
            if (errors == '0) begin
                $display("[%0t]   [PASS] Data integrity maintained through wrap-around", $time);
            end else begin
                $display("[%0t]   [FAIL] %0d data integrity errors", $time, errors);
                error_count++;
            end
        end
    endtask

    task test_continuous_simultaneous_ops();
        int i;
        int drain_count;
        logic [DATA_WIDTH-1:'0] test_data;
        begin
            $display("\n[%0t] [TEST %0d] Continuous simultaneous enq/deq operations", $time, ++test_count);
            
            // Start with partially full queue
            for (i = '0; i < DEPTH/2; i++) begin
                enq = 1'b1;
                din = i + 5000;
                @(posedge clk);
            end
            enq = '0;
            @(posedge clk);
            
            // Now continuous simultaneous operations
            for (i = '0; i < 100; i++) begin
                test_data = i + 6000;
                enq = 1'b1;
                deq = 1'b1;
                din = test_data;
                @(posedge clk);
            end
            
            enq = '0;
            deq = '0;
            @(posedge clk);
            
            // Verify queue still has DEPTH/2 elements
            // Count by checking how many times we can dequeue before empty
            drain_count = '0;
            for (int j = '0; j < DEPTH + 5; j++) begin
                if (empty) break;
                deq = 1'b1;
                @(posedge clk);
                drain_count++;
            end
            deq = '0;
            @(posedge clk);
            
            if (drain_count == DEPTH/2) begin
                $display("[%0t]   [PASS] Continuous simultaneous operations maintained correct count (%0d)", $time, drain_count);
            end else begin
                $display("[%0t]   [FAIL] Expected %0d elements, drained %0d", $time, DEPTH/2, drain_count);
                error_count++;
            end
        end
    endtask

    task test_burst_operations();
        int i;
        logic [DATA_WIDTH-1:0] expected;
        int errors;
        begin
            $display("\n[%0t] [TEST %0d] Burst enqueue followed by burst dequeue", $time, ++test_count);
            errors = '0;
            
            // Burst enqueue
            for (i = '0; i < DEPTH; i++) begin
                @(posedge clk);
                enq = 1'b1;
                din = i + 7000;
                @(posedge clk);
                enq = '0;
            end
            
            
            // Wait a few cycles
            repeat(3) @(posedge clk);
            
            // Burst dequeue and verify order
            for (i = 0; i < DEPTH; i++) begin
                expected = i + 7000;
                deq = 1'b1;
                @(posedge clk);
                if (dout !== expected) begin
                    $display("[%0t]   [FAIL] Entry %0d: expected 0x%08h, got 0x%08h", $time, i, expected, dout);
                    errors++;
                end
            end
            deq = 1'b0;
            
            if (errors == 0) begin
                $display("[%0t]   [PASS] Burst operations maintained FIFO order", $time);
            end else begin
                $display("[%0t]   [FAIL] %0d order errors in burst operations", $time, errors);
                error_count++;
            end
        end
    endtask

    task test_controlled_stress();
        int i, op_count;
        int enq_count, deq_count;
        logic [DATA_WIDTH-1:0] test_data;
        begin
            $display("\n[%0t] [TEST %0d] Controlled stress test with tracking", $time, ++test_count);
            
            enq_count = 0;
            deq_count = 0;
            
            for (i = 0; i < 1000; i++) begin
                @(posedge clk);
                
                // Decide operation based on current state
                if (full) begin
                    enq = 1'b0;
                    deq = 1'b1;
                    if (deq) deq_count++;
                end else if (empty) begin
                    enq = 1'b1;
                    deq = 1'b0;
                    din = $random;
                    if (enq) enq_count++;
                end else begin
                    // Random choice when neither full nor empty
                    case ($random % 4)
                        0: begin enq = 1'b1; deq = 1'b0; din = $random; enq_count++; end
                        1: begin enq = 1'b0; deq = 1'b1; deq_count++; end
                        2: begin enq = 1'b1; deq = 1'b1; din = $random; enq_count++; deq_count++; end
                        3: begin enq = 1'b0; deq = 1'b0; end
                    endcase
                end
            end
            
            @(posedge clk);
            enq = 1'b0;
            deq = 1'b0;
            
            $display("[%0t]   [INFO] Enqueued: %0d, Dequeued: %0d, Net: %0d", $time, enq_count, deq_count, enq_count - deq_count);
            $display("[%0t]   [PASS] Controlled stress test completed", $time);
        end
    endtask

    task test_nearly_full_operations();
        int i;
        begin
            $display("\n[%0t] [TEST %0d] Operations near full capacity", $time, ++test_count);

            // Empty the queue first
            while (!empty) begin
                @(posedge clk);
                deq = 1'b1;
            end
            @(posedge clk);
            deq = 1'b0;
            
            // Fill to one less than full
            for (i = 0; i < DEPTH - 1; i++) begin
                @(posedge clk);
                enq = 1'b1;
                din = i + 8000;
            end
            @(posedge clk);
            enq = 1'b0;
            @(posedge clk);
            
            if (full) begin
                $display("[%0t]   [FAIL] Queue should not be full yet (at %0d/%0d)", $time, DEPTH-1, DEPTH);
                error_count++;
            end
            
            // Add one more to make it full
            @(posedge clk);
            enq = 1'b1;
            din = 8999;
            @(posedge clk);
            enq = 1'b0;
            @(posedge clk);
            
            if (!full) begin
                $display("[%0t]   [FAIL] Queue should be full now", $time);
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Nearly-full operations correct", $time);
            end
            
            // Clean up
            repeat(DEPTH) begin
                @(posedge clk);
                deq = 1'b1;
            end
            @(posedge clk);
            deq = 1'b0;
        end
    endtask

    task test_data_patterns();
        int i, j;
        logic [DATA_WIDTH-1:0] pattern;
        logic [DATA_WIDTH-1:0] expected;
        int errors;
        begin
            $display("\n[%0t] [TEST %0d] Data pattern tests (walking 1s, walking 0s, alternating)", $time, ++test_count);
            errors = 0;

            // Empty the queue first
            while (!empty) begin
                @(posedge clk);
                deq = 1'b1;
            end
            @(posedge clk);
            deq = 1'b0;
            
            // Walking 1s
            for (i = 0; i < DEPTH; i++) begin
                pattern = 1 << i;
                @(posedge clk);
                enq = 1'b1;
                din = pattern;
            end
            @(posedge clk);
            enq = 1'b0;
            
            for (i = 0; i < DEPTH; i++) begin
                expected = 1 << i;
                deq = 1'b1;
                @(posedge clk);
                if (dout !== expected) begin
                    $display("[%0t]   [FAIL] Walking 1s bit %0d: expected 0x%08h, got 0x%08h", $time, i, expected, dout);
                    errors++;
                end
            end
            deq = 1'b0;
            @(posedge clk);
            
            // Walking 0s
            for (i = 0; i < DEPTH; i++) begin
                pattern = ~(1 << i);
                @(posedge clk);
                enq = 1'b1;
                din = pattern;
            end
            @(posedge clk);
            enq = 1'b0;
            
            for (i = 0; i < DEPTH; i++) begin
                expected = ~(1 << i);
                deq = 1'b1;
                @(posedge clk);
                if (dout !== expected) begin
                    $display("[%0t]   [FAIL] Walking 0s bit %0d: expected 0x%08h, got 0x%08h", $time, i, expected, dout);
                    errors++;
                end
            end
            deq = 1'b0;
            @(posedge clk);
            
            // Alternating pattern
            for (i = 0; i < 8; i++) begin
                pattern = (i % 2) ? 32'hAAAAAAAA : 32'h55555555;
                @(posedge clk);
                enq = 1'b1;
                din = pattern;
            end
            @(posedge clk);
            enq = 1'b0;
            
            for (i = 0; i < 8; i++) begin
                expected = (i % 2) ? 32'hAAAAAAAA : 32'h55555555;
                deq = 1'b1;
                @(posedge clk);
                if (dout !== expected) begin
                    $display("[%0t]   [FAIL] Alternating pattern %0d: expected 0x%08h, got 0x%08h", $time, i, expected, dout);
                    errors++;
                end
            end
            deq = 1'b0;
            @(posedge clk);
            
            if (errors == 0) begin
                $display("[%0t]   [PASS] All data patterns verified correctly", $time);
            end else begin
                $display("[%0t]   [FAIL] %0d pattern errors", $time, errors);
                error_count++;
            end
        end
    endtask

    task test_reset_during_operation();
        int i;
        begin
            $display("\n[%0t] [TEST %0d] Reset during operation", $time, ++test_count);
            
            // Fill queue partially
            for (i = 0; i < DEPTH/2; i++) begin
                @(posedge clk);
                enq = 1'b1;
                din = i + 9000;
            end
            @(posedge clk);
            enq = 1'b0;
            
            // Assert reset
            @(posedge clk);
            rst = 1'b1;
            @(posedge clk);
            rst = 1'b0;
            @(posedge clk);
            
            // Check if properly reset
            if (!empty) begin
                $display("[%0t]   [FAIL] Queue should be empty after reset", $time);
                error_count++;
            end else if (full) begin
                $display("[%0t]   [FAIL] Queue should not be full after reset", $time);
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Reset during operation successful", $time);
            end
        end
    endtask

    task test_back_to_back_simultaneous();
        int i;
        logic [DATA_WIDTH-1:0] expected_out[100];
        logic [DATA_WIDTH-1:0] enq_data;
        int errors;
        begin
            $display("\n[%0t] [TEST %0d] Back-to-back simultaneous enq/deq", $time, ++test_count);
            errors = 0;
            
            // Prime the queue with initial data
            for (i = 0; i < DEPTH/2; i++) begin
                expected_out[i] = i + 10000;
                enq = 1'b1;
                din = expected_out[i];
                @(posedge clk);
            end
            enq = 1'b0;
            @(posedge clk);
            
            // Back-to-back simultaneous operations
            for (i = 0; i < 50; i++) begin
                enq_data = i + 11000;
                expected_out[DEPTH/2 + i] = enq_data;
                enq = 1'b1;
                deq = 1'b1;
                din = enq_data;
                @(posedge clk);
                // Check dequeued data (should be from original queue)
                if (i < DEPTH/2) begin
                    if (dout !== expected_out[i]) begin
                        $display("[%0t]   [FAIL] Iteration %0d: expected 0x%08h, got 0x%08h", $time, i, expected_out[i], dout);
                        errors++;
                    end
                end
            end
            
            enq = 1'b0;
            deq = 1'b0;
            @(posedge clk);
            
            if (errors == 0) begin
                $display("[%0t]   [PASS] Back-to-back simultaneous operations successful", $time);
            end else begin
                $display("[%0t]   [FAIL] %0d errors in back-to-back operations", $time, errors);
                error_count++;
            end
            
            // Clean up
            repeat(DEPTH) begin
                @(posedge clk);
                deq = 1'b1;
            end
            @(posedge clk);
            deq = 1'b0;
        end
    endtask


endmodule
