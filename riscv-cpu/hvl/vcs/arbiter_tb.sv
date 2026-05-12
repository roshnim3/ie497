`timescale 1ps/1ps

module arbiter_tb;

    // ========================================
    // Clock / Reset
    // ========================================
    timeunit 1ps;
    timeprecision 1ps;

    int clock_half_period_ps;
    initial begin
        if (!$value$plusargs("CLOCK_PERIOD_PS_ECE411=%d", clock_half_period_ps))
            clock_half_period_ps = 10000;  // default 10 ns period
        clock_half_period_ps = clock_half_period_ps / 2;
    end

    bit clk = 1'b0;
    always #(clock_half_period_ps) clk = ~clk;
    bit rst;

    // ========================================
    // DUT I/O
    // ========================================
    logic [31:0] req_addr;
    logic        req_valid;
    logic        req_read;
    logic        req_write;
    logic [63:0] req_data;

    logic [63:0] burst_data;
    logic        burst_valid;
    logic [31:0] burst_addr;
    logic        arb_ready;

    // Arb <-> DRAM
    logic [31:0] bmem_addr;
    logic        bmem_read;
    logic        bmem_write;
    logic [63:0] bmem_wdata;

    logic        bmem_ready;
    logic [31:0] bmem_raddr;
    logic [63:0] bmem_rdata;
    logic        bmem_rvalid;

    // ========================================
    // Tracking
    // ========================================
    int error_count;
    int test_count;

    // ========================================
    // DUT
    // ========================================
    arbiter #(.ADDR_WIDTH(32)) dut (
        .clk(clk), .rst(rst),
        // Instruction adapter (tied off for now)
        .i_req_addr('0),
        .i_req_read(1'b0),
        .i_req_write(1'b0),
        .i_req_data('0),
        .i_burst_data(),  // unconnected
        .i_burst_valid(),
        .i_burst_addr(),
        .i_arb_ready(),
        // Data adapter (connected to testbench)
        .d_req_addr(req_addr),
        .d_req_read(req_read),
        .d_req_write(req_write),
        .d_req_data(req_data),
        .d_burst_data(burst_data),
        .d_burst_valid(burst_valid),
        .d_burst_addr(burst_addr),
        .d_arb_ready(arb_ready),
        // BMEM interface
        .bmem_addr(bmem_addr),
        .bmem_read(bmem_read),
        .bmem_write(bmem_write),
        .bmem_wdata(bmem_wdata),
        .bmem_ready(bmem_ready),
        .bmem_raddr(bmem_raddr),
        .bmem_rdata(bmem_rdata),
        .bmem_rvalid(bmem_rvalid)
    );

    // ========================================
    // Waveform Dump
    // ========================================
    initial begin
        $fsdbDumpfile("dump.fsdb");
        if ($test$plusargs("NO_DUMP_ALL_ECE411")) begin
            $fsdbDumpvars(0, dut, "+all");
            $fsdbDumpoff();
        end else begin
            $fsdbDumpvars(0, "+all");
        end
    end

    // ========================================
    // Main Test Sequence
    // ========================================
    initial begin
        error_count = 0;
        test_count  = 0;

        req_addr    = '0;
        req_valid   = 1'b0;
        req_read    = 1'b0;
        req_write   = 1'b0;
        req_data    = '0;

        bmem_ready  = 1'b1;
        bmem_raddr  = 32'h0;
        bmem_rdata  = 64'h0;
        bmem_rvalid = 1'b0;

        $display("========================================");
        $display("Arbiter Testbench");
        $display("========================================\n");

        // Reset
        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        // Tests
        test_single_read();
        test_two_back_to_back_reads();
        test_randomized_multi_burst();
        test_queue_full();
        // test_bmem_backpressure();
        // test_bmem_read_pulse_width();
        // test_max_queue_depth();
        // test_single_write();
        // test_single_write_backpressure();
        // test_write_backpressure_mid_burst();
        // test_multiple_writes_back_to_back();

        // Summary
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_count);
        $display("Errors: %0d", error_count);
        if (error_count == 0)
            $display("Status: ALL TESTS PASSED!");
        else
            $display("Status: SOME TESTS FAILED!");
        $display("========================================\n");

        $finish;
    end

    // ========================================
    // Helper: 4-burst DRAM response (back-to-back, no gaps)
    // ========================================
    task automatic drive_dram_read4(input logic [31:0] A, input logic [63:0] base);
        integer unsigned i;
        // Start driving immediately, no initial clock wait
        // All 4 beats back-to-back
        for (i = 0; i < 4; i++) begin
            @(posedge clk);
            #1;
            bmem_rvalid = 1'b1;
            bmem_raddr  = A;
            bmem_rdata  = (base ^ i);
        end
        // After 4 beats, drop rvalid
        @(posedge clk);
        #1;
        bmem_rvalid = 1'b0;
        bmem_raddr  = 'x;
        bmem_rdata  = 'x;
    endtask

    task automatic check_adapter_bursts4(input logic [31:0] A, input logic [63:0] base);
        integer unsigned i;
        for (i = 0; i < 4; i++) begin
            // Wait for burst data to appear
            @(posedge clk);
            #2; // Slightly larger delay to ensure driver's #1 has completed
            if (!burst_valid) begin
                $display("[%0t]   [FAIL] Expected burst_valid=1 for beat %0d", $time, i);
                error_count++;
            end else if (burst_addr !== A || burst_data !== (base ^ i)) begin
                $display("[%0t]   [FAIL] Beat %0d mismatch: got addr=0x%08h data=0x%016h, exp addr=0x%08h data=0x%016h",
                         $time, i, burst_addr, burst_data, A, (base ^ i));
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Beat %0d OK (addr=0x%08h data=0x%016h)",
                         $time, i, burst_addr, burst_data);
            end
        end
        // Verify rvalid drops after 4 beats
        @(posedge clk);
        #2;
        if (burst_valid) begin
            $display("[%0t]   [FAIL] burst_valid should be 0 after 4 beats", $time);
            error_count++;
        end
    endtask

    // ========================================
    // Driver helper: send one-cycle read header
    // ========================================
    task automatic send_read_header(input logic [31:0] A);
        // Caller controls clock timing - just set signals
        req_addr  = A;
        req_read  = 1'b1;
        req_write = 1'b0;
        req_valid = 1'b1;
        req_data  = '0;
        @(posedge clk);
        #1;
        req_valid = 1'b0;
        req_read  = 1'b0;
    endtask

    // ========================================
    // Driver helper: send one-cycle write header (4-cycle burst for data)
    // ========================================
    task automatic send_write_header(input logic [31:0] A, input logic [63:0] data);
        integer unsigned i;
        // Write takes 4 cycles with write high and different wdata each cycle
        // Must respect arb_ready - only advance to next beat when arbiter accepts current beat
        for (i = 0; i < 4; i++) begin
            // Present the beat data
            req_addr  = A;
            req_write = 1'b1;
            req_read  = 1'b0;
            req_valid = 1'b1;
            req_data  = data ^ i;  // Different data each beat
            
            // Wait for arbiter to accept (arb_ready high) before advancing to next beat
            @(posedge clk);
            #1;
            while (!arb_ready) begin
                // Hold current beat data until accepted
                @(posedge clk);
                #1;
            end
            // Now arb_ready is high, we can advance to next beat on next iteration
        end
        req_valid = 1'b0;
        req_write = 1'b0;
        req_addr  = 'x;
        req_data  = 'x;
    endtask

    // ========================================
    // Helper: Check write was issued correctly (NO rdata expected for writes!)
    // ========================================
    task automatic check_write_issued(input logic [31:0] exp_addr, input logic [63:0] exp_data_base);
        integer unsigned i;
        // The arbiter registers inputs with 1-cycle delay
        // TB sends beats 0,1,2,3 over cycles N, N+1, N+2, N+3
        // Arbiter outputs beats 0,1,2,3 over cycles N+1, N+2, N+3, N+4
        
        // Wait for bmem_write rising edge (arbiter starts outputting)
        @(posedge bmem_write);
        // @(posedge clk);  // Sync to next clock edge
        
        // Now check all 4 beats
        for (i = 0; i < 4; i++) begin
            #1;  // Small delay to let signals settle
            
            // Check that write is high
            if (!bmem_write) begin
                $display("[%0t]   [FAIL] bmem_write should be high for 4 beats, dropped at beat %0d", $time, i);
                error_count++;
                return;
            end
            
            if (bmem_addr !== exp_addr) begin
                $display("[%0t]   [FAIL] Write beat %0d address mismatch: got 0x%08h, exp 0x%08h", $time, i, bmem_addr, exp_addr);
                error_count++;
            end else if (bmem_wdata !== (exp_data_base ^ i)) begin
                $display("[%0t]   [FAIL] Write beat %0d data mismatch: got 0x%016h, exp 0x%016h", $time, i, bmem_wdata, (exp_data_base ^ i));
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Write beat %0d OK (addr=0x%08h data=0x%016h)", $time, i, bmem_addr, bmem_wdata);
            end
            
            // Move to next cycle for next beat
            @(posedge clk);
            $display("[%0t]   [INFO] Moved to next cycle for beat %0d", $time, i + 1);
        end
        
        
        
        // Verify NO rdata activity during writes (check throughout the write)
        // (Already checked implicitly - test would fail if rdata appeared)
    endtask

    // ========================================
    // TEST 1: Single Read (4-beat return)
    // ========================================
    task test_single_read();
        logic [31:0] A;
        logic [63:0] base;
        logic [31:0] issued;  // declare separately, then assign
        begin
            $display("\n[%0t] [TEST %0d] Single read request (4-beat burst)", $time, ++test_count);

            bmem_ready = 1'b1;
            A    = 32'h0000_1000;
            base = 64'hDEAD_BEEF_0000_0000;
            

            @(posedge clk);
            #1;
            send_read_header(A);

            // Expect a bmem_read pulse soon - capture address when bmem_read is high
            wait (bmem_read);
            issued = bmem_addr;  // Capture immediately, don't wait for clock
            @(posedge clk);
            $display("[%0t]   [INFO] DUT issued read @0x%08h", $time, issued);

            fork
                drive_dram_read4(issued, base);
                check_adapter_bursts4(issued, base);
            join
            
            // Wait a few cycles before next test
            // repeat (5) @(posedge clk);
        end
    endtask

    // ========================================
    // TEST 2: Two Back-to-Back Reads with Backpressure
    // ========================================
    task test_two_back_to_back_reads();
        logic [31:0] A0, A1;
        logic [63:0] base0, base1;
        logic [31:0] issued0;
        logic [31:0] issued1;
        begin
            $display("\n[%0t] [TEST %0d] Two reads with bmem backpressure between them", $time, ++test_count);
            bmem_ready = 1'b1;
            A0 = 32'h0000_2000;
            A1 = 32'h0000_3000;
            base0 = 64'hAAAA_BBBB_0000_0000;
            base1 = 64'hCCCC_DDDD_1111_1111;

            // Send first read request
            @(posedge clk);
            #1;
            req_addr  = A0;
            req_read  = 1'b1;
            req_write = 1'b0;
            req_valid = 1'b1;

            // Set bmem_ready low for 3 cycles
            @(posedge clk);
            #1;
            bmem_ready = 1'b0;
            req_valid = 1'b0;
            req_read  = 1'b0;
            $display("[%0t]   [INFO] bmem_ready set to LOW for 3 cycles", $time);

            // Hold bmem_ready low for 3 cycles total
            repeat (3) @(posedge clk);
            
            // Set bmem_ready high and send second read request
            #1;
            bmem_ready = 1'b1;
            req_addr  = A1;
            req_read  = 1'b1;
            req_write = 1'b0;
            req_valid = 1'b1;
            $display("[%0t]   [INFO] bmem_ready set to HIGH, sending second request", $time);

            @(posedge clk);
            #1;
            req_valid = 1'b0;
            req_read  = 1'b0;
            
            // Capture first read address
            wait (bmem_read);
            issued0 = bmem_addr;
            @(posedge clk);
            $display("[%0t]   [INFO] Captured first read @0x%08h", $time, issued0);
            
            // Capture second read address
            wait (bmem_read);
            issued1 = bmem_addr;
            @(posedge clk);
            $display("[%0t]   [INFO] Captured second read @0x%08h", $time, issued1);

            $display("[%0t]   [INFO] Issued reads @0x%08h and @0x%08h", $time, issued0, issued1);

            // Service first read
            fork
                drive_dram_read4(issued0, base0);
                check_adapter_bursts4(issued0, base0);
            join
            
            // Service second read
            fork
                drive_dram_read4(issued1, base1);
                check_adapter_bursts4(issued1, base1);
            join
            
            // Wait a few cycles before next test
            // repeat (5) @(posedge clk);
        end
    endtask

    // ========================================
    // TEST 3: Randomized Multi-Burst with Backpressure
    // ========================================
    task test_randomized_multi_burst();
        static integer num_reads = 10;
        integer r;
        logic [31:0] issuedA;
        logic [31:0] A;
        logic [63:0] base;
        begin
            $display("\n[%0t] [TEST %0d] Randomized multi-burst with backpressure", $time, ++test_count);
            bmem_ready = 1'b1;

            for (r = 0; r < num_reads; r++) begin
                A    = 32'h4000 + (r * 32'h10);
                base = 64'h1000_0000_0000_0000 + r;

                @(posedge clk);
                #1;
                send_read_header(A);

                // random ready toggle
                if ($urandom_range(3,0) == 0) begin
                    static integer low_cycles = $urandom_range(3,0);
                    bmem_ready = 1'b0;
                    repeat (low_cycles) @(posedge clk);
                    bmem_ready = 1'b1;
                    $display("[%0t]   [INFO] DRAM backpressure %0d cycles", $time, low_cycles);
                end

                // handle each read as soon as arbiter issues it - capture address when bmem_read is high
                wait (bmem_read);
                issuedA = bmem_addr;  // Capture immediately, don't wait for clock
                @(posedge clk);
                $display("[%0t]   [INFO] DUT issued read #%0d @0x%08h", $time, r, issuedA);

                fork
                    drive_dram_read4(issuedA, base);
                    check_adapter_bursts4(issuedA, base);
                join
            end
        end
    endtask

    // ========================================
    // TEST 4: Multiple Sequential Reads (bmem handles queuing)
    // ========================================
    task test_queue_full();
        logic [31:0] addrs[8];
        logic [63:0] bases[8];
        logic [31:0] issued[8];
        integer captured;
        integer unsigned i;
        begin
            $display("\n[%0t] [TEST %0d] Multiple sequential requests (bmem queues internally)", $time, ++test_count);
            bmem_ready = 1'b1;
            
            // Prepare test data
            for (i = 0; i < 8; i++) begin
                addrs[i] = 32'h5000 + (i * 32'h100);
                bases[i] = 64'h5555_0000_0000_0000 + i;
            end
            
            // Send 8 requests sequentially
            for (i = 0; i < 8; i++) begin
                @(posedge clk);
                #1;
                send_read_header(addrs[i]);
                
                // Capture issued address
                wait (bmem_read);
                issued[i] = bmem_addr;
                @(posedge clk);
                $display("[%0t]   [INFO] Issued read #%0d @0x%08h", $time, i, issued[i]);
                
                // Verify address
                if (issued[i] !== addrs[i]) begin
                    $display("[%0t]   [FAIL] Address %0d mismatch: got 0x%08h, exp 0x%08h", 
                             $time, i, issued[i], addrs[i]);
                    error_count++;
                end else begin
                    $display("[%0t]   [PASS] Address %0d correct (0x%08h)", $time, i, issued[i]);
                end
                
                // Service the read
                fork
                    drive_dram_read4(issued[i], bases[i]);
                    check_adapter_bursts4(issued[i], bases[i]);
                join
            end
            
            repeat (5) @(posedge clk);
        end
    endtask

    // ========================================
    // TEST 5: DRAM Backpressure Test
    // ========================================
    task test_bmem_backpressure();
        logic [31:0] A0, A1;
        logic [63:0] base0, base1;
        logic [31:0] issued0, issued1;
        begin
            $display("\n[%0t] [TEST %0d] DRAM backpressure test", $time, ++test_count);
            
            A0 = 32'h6000;
            A1 = 32'h6100;
            base0 = 64'h6666_0000_0000_0000;
            base1 = 64'h7777_0000_0000_0000;
            
            // Apply backpressure FIRST, then send request
            @(posedge clk);
            #1;
            bmem_ready = 1'b0;
            $display("[%0t]   [INFO] DRAM backpressure active", $time);
            
            // Send first request while bmem is NOT ready
            send_read_header(A0);
            
            // Hold backpressure for a few cycles
            repeat (5) @(posedge clk);
            
            // Release backpressure - request should now go through
            #1;
            bmem_ready = 1'b1;
            $display("[%0t]   [INFO] DRAM backpressure released", $time);
            
            // Capture first read (should happen now)
            wait (bmem_read);
            issued0 = bmem_addr;
            @(posedge clk);
            $display("[%0t]   [INFO] Issued first read @0x%08h", $time, issued0);
            
            // Send second request with bmem ready
            #1;
            send_read_header(A1);
            
            // Capture second read
            wait (bmem_read);
            issued1 = bmem_addr;
            @(posedge clk);
            $display("[%0t]   [INFO] Issued second read @0x%08h", $time, issued1);
            
            // Verify and service reads
            if (issued0 !== A0) begin
                $display("[%0t]   [FAIL] First address mismatch: got 0x%08h, exp 0x%08h", $time, issued0, A0);
                error_count++;
            end
            if (issued1 !== A1) begin
                $display("[%0t]   [FAIL] Second address mismatch: got 0x%08h, exp 0x%08h", $time, issued1, A1);
                error_count++;
            end
            
            fork
                drive_dram_read4(issued0, base0);
                check_adapter_bursts4(issued0, base0);
            join
            fork
                drive_dram_read4(issued1, base1);
                check_adapter_bursts4(issued1, base1);
            join
            
            repeat (5) @(posedge clk);
        end
    endtask

    // ========================================
    // TEST 6: bmem_read Pulse Width Verification
    // ========================================
    task test_bmem_read_pulse_width();
        logic [31:0] A;
        logic [63:0] base;
        logic [31:0] issued;
        integer pulse_width;
        integer num_pulses;
        integer unsigned i;
        logic prev_bmem_read;
        begin
            $display("\n[%0t] [TEST %0d] Verify bmem_read pulse width is 1 cycle", $time, ++test_count);
            
            A = 32'h7000;
            base = 64'h9999_0000_0000_0000;
            bmem_ready = 1'b1;
            
            @(posedge clk);
            #1;
            send_read_header(A);
            
            // Monitor bmem_read pulse
            num_pulses = 0;
            pulse_width = 0;
            prev_bmem_read = 1'b0;
            
            fork
                // Capture issued address
                begin
                    @(posedge clk iff bmem_read);
                    issued = bmem_addr;
                    $display("[%0t]   [INFO] DUT issued read @0x%08h", $time, issued);
                end
                
                // Monitor pulse width
                begin
                    for (i = 0; i < 20; i++) begin
                        @(posedge clk);
                        if (bmem_read && !prev_bmem_read) begin
                            // Rising edge
                            num_pulses++;
                            pulse_width = 1;
                            $display("[%0t]   [INFO] bmem_read rising edge detected (pulse #%0d)", $time, num_pulses);
                        end else if (bmem_read && prev_bmem_read) begin
                            // Still high
                            pulse_width++;
                            $display("[%0t]   [WARN] bmem_read still high (cycle %0d)", $time, pulse_width);
                        end else if (!bmem_read && prev_bmem_read) begin
                            // Falling edge
                            $display("[%0t]   [INFO] bmem_read falling edge (total width: %0d cycles)", $time, pulse_width);
                            if (pulse_width != 1) begin
                                $display("[%0t]   [FAIL] Pulse width should be 1 cycle, got %0d", $time, pulse_width);
                                error_count++;
                            end else begin
                                $display("[%0t]   [PASS] Pulse width correct (1 cycle)", $time);
                            end
                        end
                        prev_bmem_read = bmem_read;
                    end
                end
            join
            
            if (num_pulses != 1) begin
                $display("[%0t]   [FAIL] Expected 1 pulse, got %0d", $time, num_pulses);
                error_count++;
            end
            
            // Service the read
            fork
                drive_dram_read4(issued, base);
                check_adapter_bursts4(issued, base);
            join
            
            repeat (5) @(posedge clk);
        end
    endtask

    // ========================================
    // TEST 7: Multiple Requests in Pipeline
    // ========================================
    task test_max_queue_depth();
        logic [31:0] A;
        logic [63:0] base;
        static integer num_requests = 5;
        integer r;
        begin
            $display("\n[%0t] [TEST %0d] Multiple requests in pipeline", $time, ++test_count);
            bmem_ready = 1'b1;
            
            for (r = 0; r < num_requests; r++) begin
                A = 32'h8000 + (r * 32'h200);
                base = 64'hAAAA_0000_0000_0000 + r;
                
                // Send request
                @(posedge clk);
                #1;
                send_read_header(A);
                
                // Capture when issued
                wait (bmem_read);
                if (bmem_addr != A) begin
                    $display("[%0t]   [FAIL] Request %0d: Expected addr 0x%08h, got 0x%08h", $time, r, A, bmem_addr);
                    error_count++;
                end else begin
                    $display("[%0t]   [INFO] Request %0d issued correctly @0x%08h", $time, r, A);
                end
                @(posedge clk);
                
                // Service and check
                fork
                    drive_dram_read4(A, base);
                    check_adapter_bursts4(A, base);
                join
            end
            
            $display("[%0t]   [PASS] All %0d requests handled correctly in pipeline", $time, num_requests);
            repeat (5) @(posedge clk);
        end
    endtask

    // ========================================
    // TEST 8: Single Write (4-cycle burst)
    // ========================================
    task test_single_write();
        logic [31:0] A;
        logic [63:0] D;
        begin
            $display("\n[%0t] [TEST %0d] Single Write Request (4-beat burst)", $time, ++test_count);
            bmem_ready = 1'b1;
            A = 32'h9000;
            D = 64'hFACE_FEED_0000_0000;

            // Send write request (4 cycles) and check in parallel
            @(posedge clk);
            #1;
            fork
                send_write_header(A, D);
                check_write_issued(A, D);
            join
            
            $display("[%0t]   [PASS] Write test completed", $time);
            
            repeat (3) @(posedge clk);
        end
    endtask

    // ========================================
    // TEST 9: Single Write with Backpressure
    // ========================================
    task test_single_write_backpressure();
        logic [31:0] A;
        logic [63:0] D;
        begin
            $display("\n[%0t] [TEST %0d] Single Write with Backpressure", $time, ++test_count);
            A = 32'hA000;
            D = 64'hDEAD_CAFE_0000_0000;

            // Apply backpressure FIRST
            @(posedge clk);
            #1;
            bmem_ready = 1'b0;
            $display("[%0t]   [INFO] DRAM backpressure active", $time);
            
            // Send write request in parallel with releasing backpressure
            fork
                // Send the write - will stall on first beat until bmem_ready goes high
                send_write_header(A, D);
                
                // Release backpressure after a few cycles
                begin
                    repeat (4) @(posedge clk);
                    #1;
                    bmem_ready = 1'b1;
                    $display("[%0t]   [INFO] DRAM backpressure released", $time);
                end
                
                // Check that write was issued correctly (4 beats, NO rdata)
                check_write_issued(A, D);
            join
            
            $display("[%0t]   [PASS] Write with backpressure test completed", $time);
            
            repeat (3) @(posedge clk);
        end
    endtask

    // ========================================
    // TEST 10: Write with Backpressure Mid-Burst
    // ========================================
    task test_write_backpressure_mid_burst();
        logic [31:0] A;
        logic [63:0] D;
        integer beat_count;
        begin
            $display("\n[%0t] [TEST %0d] Write with Backpressure Mid-Burst", $time, ++test_count);
            A = 32'hA000;
            D = 64'hCAFE_BABE_0000_0000;
            bmem_ready = 1'b1;

            @(posedge clk);
            #1;
            
            // Send write and apply backpressure after 2nd beat
            fork
                // Send the write (4 beats)
                begin
                    integer i;
                    for (i = 0; i < 4; i++) begin
                        req_addr  = A;
                        req_write = 1'b1;
                        req_read  = 1'b0;
                        req_valid = 1'b1;
                        req_data  = D ^ i;
                        
                        // Wait for arbiter to accept before advancing to next beat
                        @(posedge clk);
                        #1;
                        while (!arb_ready) begin
                            @(posedge clk);
                            #1;
                        end
                    end
                    req_valid = 1'b0;
                    req_write = 1'b0;
                    req_addr  = 'x;
                    req_data  = 'x;
                    $display("[%0t]   [INFO] Finished sending all 4 beats", $time);
                end
                
                // Apply backpressure after 2nd beat is forwarded
                begin
                    // Wait for first beat to be output
                    @(posedge clk iff bmem_write);
                    $display("[%0t]   [INFO] Beat 0 forwarded to bmem", $time);
                    
                    // Wait for second beat
                    @(posedge clk iff bmem_write);
                    $display("[%0t]   [INFO] Beat 1 forwarded to bmem", $time);
                    
                    // Apply backpressure
                    @(posedge clk);
                    #1;
                    bmem_ready = 1'b0;
                    $display("[%0t]   [INFO] Backpressure applied after beat 1", $time);
                    
                    // Hold for a few cycles
                    repeat (3) @(posedge clk);
                    #1;
                    bmem_ready = 1'b1;
                    $display("[%0t]   [INFO] Backpressure released", $time);
                end
                
                // Check all 4 beats are output correctly (no duplicates!)
                begin
                    integer j;
                    logic [63:0] expected_data;
                    logic [31:0] beat_addrs[4];
                    logic [63:0] beat_data[4];
                    beat_count = 0;
                    
                    // Collect all bmem_write transactions
                    while (beat_count < 4) begin
                        @(posedge clk);
                        #1;
                        if (bmem_write) begin
                            beat_addrs[beat_count] = bmem_addr;
                            beat_data[beat_count] = bmem_wdata;
                            $display("[%0t]   [INFO] Captured beat %0d: addr=0x%08h data=0x%016h", 
                                     $time, beat_count, bmem_addr, bmem_wdata);
                            beat_count++;
                        end
                    end
                    
                    // Verify we got exactly 4 beats with correct data
                    for (j = 0; j < 4; j++) begin
                        expected_data = D ^ j;
                        if (beat_addrs[j] !== A) begin
                            $display("[%0t]   [FAIL] Beat %0d address mismatch: got 0x%08h, exp 0x%08h", 
                                     $time, j, beat_addrs[j], A);
                            error_count++;
                        end else if (beat_data[j] !== expected_data) begin
                            $display("[%0t]   [FAIL] Beat %0d data mismatch: got 0x%016h, exp 0x%016h", 
                                     $time, j, beat_data[j], expected_data);
                            error_count++;
                        end else begin
                            $display("[%0t]   [PASS] Beat %0d correct", $time, j);
                        end
                    end
                    
                    // Check for any extra beats (duplicates)
                    repeat (5) @(posedge clk);
                    #1;
                    if (bmem_write) begin
                        $display("[%0t]   [FAIL] Extra bmem_write detected after 4 beats!", $time);
                        error_count++;
                    end
                end
            join
            
            $display("[%0t]   [PASS] Write with mid-burst backpressure test completed", $time);
            
            repeat (3) @(posedge clk);
        end
    endtask

    // ========================================
    // TEST 11: Multiple Back-to-Back Writes
    // ========================================
    task test_multiple_writes_back_to_back();
        logic [31:0] A0, A1;
        logic [63:0] D0, D1;
        begin
            $display("\n[%0t] [TEST %0d] Multiple Back-to-Back Writes", $time, ++test_count);
            bmem_ready = 1'b1;
            A0 = 32'hB000;
            A1 = 32'hB100;
            D0 = 64'h1234_5678_0000_0000;
            D1 = 64'hABCD_EF00_0000_0000;

            @(posedge clk);
            #1;
            
            // Send and check both writes in parallel
            fork
                // Send both writes back-to-back
                begin
                    integer unsigned i;
                    // First write (4 beats)
                    for (i = 0; i < 4; i++) begin
                        req_addr  = A0;
                        req_write = 1'b1;
                        req_read  = 1'b0;
                        req_valid = 1'b1;
                        req_data  = D0 ^ i;
                        
                        // Wait for arbiter to accept before advancing to next beat
                        @(posedge clk);
                        #1;
                        while (!arb_ready) begin
                            @(posedge clk);
                            #1;
                        end
                    end
                    
                    // Second write immediately follows (4 beats)
                    for (i = 0; i < 4; i++) begin
                        req_addr  = A1;
                        req_write = 1'b1;
                        req_read  = 1'b0;
                        req_valid = 1'b1;
                        req_data  = D1 ^ i;
                        
                        // Wait for arbiter to accept before advancing to next beat
                        @(posedge clk);
                        #1;
                        while (!arb_ready) begin
                            @(posedge clk);
                            #1;
                        end
                    end
                    
                    req_valid = 1'b0;
                    req_write = 1'b0;
                    req_addr  = 'x;
                    req_data  = 'x;
                    
                    $display("[%0t]   [INFO] Sent two back-to-back write requests", $time);
                end
                
                // Check both writes
                begin
                    // Wait for first write to start
                    @(posedge bmem_write);
                    
                    // Check first write (4 beats)
                    for (integer j = 0; j < 4; j++) begin
                        #1;
                        if (!bmem_write) begin
                            $display("[%0t]   [FAIL] First write: bmem_write dropped at beat %0d", $time, j);
                            error_count++;
                        end else if (bmem_addr !== A0) begin
                            $display("[%0t]   [FAIL] First write beat %0d address mismatch: got 0x%08h, exp 0x%08h", $time, j, bmem_addr, A0);
                            error_count++;
                        end else if (bmem_wdata !== (D0 ^ j)) begin
                            $display("[%0t]   [FAIL] First write beat %0d data mismatch: got 0x%016h, exp 0x%016h", $time, j, bmem_wdata, (D0 ^ j));
                            error_count++;
                        end else begin
                            $display("[%0t]   [PASS] First write beat %0d OK (addr=0x%08h data=0x%016h)", $time, j, bmem_addr, bmem_wdata);
                        end
                        @(posedge clk);
                    end
                    
                    // Check second write (4 beats) - bmem_write should still be high
                    for (integer j = 0; j < 4; j++) begin
                        #1;
                        if (!bmem_write) begin
                            $display("[%0t]   [FAIL] Second write: bmem_write dropped at beat %0d", $time, j);
                            error_count++;
                        end else if (bmem_addr !== A1) begin
                            $display("[%0t]   [FAIL] Second write beat %0d address mismatch: got 0x%08h, exp 0x%08h", $time, j, bmem_addr, A1);
                            error_count++;
                        end else if (bmem_wdata !== (D1 ^ j)) begin
                            $display("[%0t]   [FAIL] Second write beat %0d data mismatch: got 0x%016h, exp 0x%016h", $time, j, bmem_wdata, (D1 ^ j));
                            error_count++;
                        end else begin
                            $display("[%0t]   [PASS] Second write beat %0d OK (addr=0x%08h data=0x%016h)", $time, j, bmem_addr, bmem_wdata);
                        end
                        @(posedge clk);
                    end
                    
                    // Verify bmem_write drops after both writes
                    #1;
                    if (bmem_write) begin
                        $display("[%0t]   [FAIL] bmem_write should be 0 after both writes", $time);
                        error_count++;
                    end
                end
            join
            
            $display("[%0t]   [PASS] Back-to-back writes test completed", $time);
            
            repeat (3) @(posedge clk);
        end
    endtask
endmodule
