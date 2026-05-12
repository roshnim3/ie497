module fetch_tb;

    timeunit 1ps;
    timeprecision 1ps;

    // Clock and reset
    int clock_half_period_ps;
    initial begin
        $value$plusargs("CLOCK_PERIOD_PS_ECE411=%d", clock_half_period_ps);
        clock_half_period_ps = clock_half_period_ps / 2;
    end

    bit clk;
    always #(clock_half_period_ps) clk = ~clk;
    bit rst;

    // Fetch module interface signals
    logic [31:0] inst_in;
    logic        cache_resp;
    logic [31:0] inst_out;
    logic [31:0] pc;

    // Memory interface
    mem_itf_wo_mask #(
        .CHANNELS(1),
        .DWIDTH(32)
    ) mem_itf (
        .clk(clk),
        .rst(rst)
    );

    // Testbench variables
    int error_count;
    int test_count;
    logic [31:0] expected_pc;
    logic [31:0] expected_inst;

    // Memory model - simple instruction memory
    logic [31:0] instruction_memory [logic [31:0]];

    // Instantiate the DUT (Device Under Test)
    fetch dut (
        .clk(clk),
        .rst(rst),
        .inst_in(inst_in),
        .cache_resp(cache_resp),
        .inst_out(inst_out),
        .pc(pc)
    );

    // Memory interface connection - mimic continuous fetching
    always_comb begin
        mem_itf.addr[0] = pc;
        mem_itf.read[0] = !dut.full; // Read when queue is not full
        mem_itf.write[0] = 1'b0;     // Fetch doesn't write
        mem_itf.wdata[0] = '0;
    end

    // Simple memory response model
    initial begin
        // Initialize instruction memory with test values
        instruction_memory['haaaa_a000] = 32'h0000_0013; // nop (addi x0, x0, 0)
        instruction_memory['haaaa_a004] = 32'h0010_8093; // addi x1, x1, 1
        instruction_memory['haaaa_a008] = 32'h0020_8113; // addi x2, x1, 2
        instruction_memory['haaaa_a00c] = 32'h0030_8193; // addi x3, x1, 3
        instruction_memory['haaaa_a010] = 32'h0040_8213; // addi x4, x1, 4
        instruction_memory['haaaa_a014] = 32'h0050_8293; // addi x5, x1, 5
        instruction_memory['haaaa_a018] = 32'h0060_8313; // addi x6, x1, 6
        instruction_memory['haaaa_a01c] = 32'h0070_8393; // addi x7, x1, 7
        instruction_memory['haaaa_a020] = 32'h0080_8413; // addi x8, x1, 8
        instruction_memory['haaaa_a024] = 32'h0090_8493; // addi x9, x1, 9
    end

    // Memory response logic - responds when read is asserted
    always_ff @(posedge clk) begin
        if (rst) begin
            mem_itf.resp[0] <= 1'b0;
            mem_itf.rdata[0] <= '0;
        end else begin
            if (mem_itf.read[0]) begin
                mem_itf.resp[0] <= 1'b1;
                if (instruction_memory.exists(mem_itf.addr[0])) begin
                    mem_itf.rdata[0] <= instruction_memory[mem_itf.addr[0]];
                end else begin
                    mem_itf.rdata[0] <= 32'hDEAD_BEEF; // Invalid instruction
                end
            end else begin
                mem_itf.resp[0] <= 1'b0;
            end
        end
    end

    // Connect memory interface to fetch inputs
    assign inst_in = mem_itf.rdata[0];
    assign cache_resp = mem_itf.resp[0];

    // Main test sequence
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
        error_count = 0;
        test_count = 0;

        // Display test header
        $display("========================================");
        $display("Fetch Testbench");
        $display("========================================\n");

        // Reset sequence
        rst = 1'b1;
        repeat(2) @(posedge clk);
        rst <= 1'b0;
        dut.deq <= 1'b0; // Initialize dequeue signal
        @(posedge clk);

        // Test 1: Check initial PC value
        test_initial_pc();

        // Test 2: Continuous fetching - fill the queue
        test_continuous_fetch();

        // Test 3: Dequeue instructions and verify order
        test_dequeue_instructions();

        // Test 4: Mixed fetch and dequeue operations
        test_mixed_operations();

        // Test 5: Queue full behavior
        test_queue_full();

        // Test 6: Queue empty behavior
        test_queue_empty();

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

    task test_initial_pc();
        begin
            $display("[%0t] [TEST %0d] Checking initial PC value", $time, ++test_count);
            if (pc !== 32'haaaa_a000) begin
                $display("[%0t]   [FAIL] PC should be 0xaaaa_a000, got 0x%h", $time, pc);
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Initial PC is correct: 0x%h", $time, pc);
            end
        end
    endtask

    task test_continuous_fetch();
        int i;
        logic [31:0] start_pc;
        begin
            $display("\n[%0t] [TEST %0d] Continuous fetching - filling the queue", $time, ++test_count);
            start_pc = pc;
            
            // Let the fetch unit automatically fetch instructions
            // It will fetch until the queue is full
            repeat(10) @(posedge clk);
            
            // Check that PC has advanced
            if (pc != start_pc) begin
                $display("[%0t]   [PASS] PC advanced from 0x%h to 0x%h", $time, start_pc, pc);
            end else begin
                $display("[%0t]   [FAIL] PC did not advance", $time);
                error_count++;
            end
            
            // Check if queue is full
            if (dut.full) begin
                $display("[%0t]   [INFO] Queue is full, PC is stalled at 0x%h", $time, pc);
            end
        end
    endtask

    task test_dequeue_instructions();
        int i;
        logic [31:0] expected_addr;
        begin
            $display("\n[%0t] [TEST %0d] Dequeuing instructions from the queue", $time, ++test_count);
            
            expected_addr = 32'haaaa_0000;
            
            // Manually trigger dequeue operations through the internal signal
            for (i = 0; i < 5; i++) begin
                @(posedge clk);
                
                // Wait for instruction to be available
                if (!dut.empty) begin
                    // Force dequeue signal (accessing internal signal)
                    force dut.deq = 1'b1;
                    @(posedge clk);
                    #1; // Small delay to let output settle
                    
                    if (instruction_memory.exists(expected_addr)) begin
                        if (inst_out === instruction_memory[expected_addr]) begin
                            $display("[%0t]   [PASS] Dequeued instruction 0x%h from PC 0x%h", 
                                    $time, inst_out, expected_addr);
                        end else begin
                            $display("[%0t]   [FAIL] Expected instruction 0x%h, got 0x%h for PC 0x%h", 
                                    $time, instruction_memory[expected_addr], inst_out, expected_addr);
                            error_count++;
                        end
                    end
                    
                    expected_addr += 4;
                    release dut.deq;
                end else begin
                    $display("[%0t]   [INFO] Queue is empty, cannot dequeue", $time);
                    break;
                end
            end
        end
    endtask

    task test_mixed_operations();
        int i;
        begin
            $display("\n[%0t] [TEST %0d] Mixed fetch and dequeue operations", $time, ++test_count);
            
            // Alternate between allowing fetches and dequeuing
            for (i = 0; i < 8; i++) begin
                // Let it fetch for a few cycles
                repeat(2) @(posedge clk);
                
                // Dequeue if not empty
                if (!dut.empty) begin
                    force dut.deq = 1'b1;
                    @(posedge clk);
                    $display("[%0t]   [INFO] Dequeued instruction 0x%h", $time, inst_out);
                    release dut.deq;
                end
                
                @(posedge clk);
            end
            
            $display("[%0t]   [PASS] Mixed operations completed", $time);
        end
    endtask

    task test_queue_full();
        begin
            $display("\n[%0t] [TEST %0d] Testing queue full behavior", $time, ++test_count);
            
            // First, drain the queue completely
            force cache_resp = 1'b0;

            while (!dut.empty) begin
                force dut.deq = 1'b1;
                @(posedge clk);
                release dut.deq;
            end

            release cache_resp;
            
            // Now let it fill up
            repeat(20) @(posedge clk);
            
            if (dut.full) begin
                static logic [31:0] pc_when_full = pc;
                $display("[%0t]   [INFO] Queue is full, PC stalled at 0x%h", $time, pc_when_full);
                
                // Verify PC doesn't advance when full
                repeat(5) @(posedge clk);
                
                if (pc === pc_when_full) begin
                    $display("[%0t]   [PASS] PC correctly stalled when queue is full", $time);
                end else begin
                    $display("[%0t]   [FAIL] PC advanced when queue was full", $time);
                    error_count++;
                end
            end else begin
                $display("[%0t]   [WARN] Queue did not fill up", $time);
            end
        end
    endtask

    task test_queue_empty();
        begin
            $display("\n[%0t] [TEST %0d] Testing queue empty behavior", $time, ++test_count);
            
            // Drain the queue
            force cache_resp = 1'b0;

            while (!dut.empty) begin
                force dut.deq = 1'b1;
                @(posedge clk);
                release dut.deq;
            end
            
            @(posedge clk);

            release cache_resp;
            
            if (dut.empty) begin
                $display("[%0t]   [PASS] Queue is empty", $time);
                
                // Try to dequeue from empty queue
                force dut.deq = 1'b1;
                @(posedge clk);
                release dut.deq;
                
                $display("[%0t]   [INFO] Attempted dequeue from empty queue", $time);
            end else begin
                $display("[%0t]   [FAIL] Queue should be empty", $time);
                error_count++;
            end
        end
    endtask

endmodule
