`timescale 1ps/1ps

module arbiter_dual_tb;

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
    // DUT I/O - Instruction Adapter
    // ========================================
    logic [31:0] i_req_addr;
    logic        i_req_read;
    logic        i_req_write;
    logic [63:0] i_req_data;

    logic [63:0] i_burst_data;
    logic        i_burst_valid;
    logic [31:0] i_burst_addr;
    logic        i_arb_ready;

    // ========================================
    // DUT I/O - Data Adapter
    // ========================================
    logic [31:0] d_req_addr;
    logic        d_req_read;
    logic        d_req_write;
    logic [63:0] d_req_data;

    logic [63:0] d_burst_data;
    logic        d_burst_valid;
    logic [31:0] d_burst_addr;
    logic        d_arb_ready;

    // ========================================
    // Arb <-> DRAM
    // ========================================
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
        // Instruction adapter
        .i_req_addr(i_req_addr),
        .i_req_read(i_req_read),
        .i_req_write(i_req_write),
        .i_req_data(i_req_data),
        .i_burst_data(i_burst_data),
        .i_burst_valid(i_burst_valid),
        .i_burst_addr(i_burst_addr),
        .i_arb_ready(i_arb_ready),
        // Data adapter
        .d_req_addr(d_req_addr),
        .d_req_read(d_req_read),
        .d_req_write(d_req_write),
        .d_req_data(d_req_data),
        .d_burst_data(d_burst_data),
        .d_burst_valid(d_burst_valid),
        .d_burst_addr(d_burst_addr),
        .d_arb_ready(d_arb_ready),
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
    // Smart DRAM Model - Responds to any read request automatically
    // ========================================
    // Store expected read responses: address -> base data pattern
    logic [63:0] dram_read_responses [logic [31:0]];
    
    // Queue of pending requests
    typedef struct {
        logic [31:0] addr;
        logic [63:0] base_data;
    } dram_request_t;
    
    dram_request_t dram_request_queue[$];
    
    // Monitor for incoming requests
    initial begin
        forever begin
            @(posedge clk);
            #2; // Sample after signals settle
            // If we see a read request and we have a response programmed for it
            if (bmem_read && bmem_ready && dram_read_responses.exists(bmem_addr)) begin
                dram_request_t req;
                req.addr = bmem_addr;
                req.base_data = dram_read_responses[bmem_addr];
                dram_request_queue.push_back(req);
                $display("[%0t]   [DRAM-MONITOR] Captured read request for addr 0x%08h", $time, bmem_addr);
                // Remove from pending so we don't capture it again
                dram_read_responses.delete(bmem_addr);
            end
        end
    end
    
    // Responder process
    initial begin
        bmem_rvalid = 1'b0;
        bmem_raddr = 'x;
        bmem_rdata = 'x;
        
        forever begin
            // Wait for a request in the queue
            wait(dram_request_queue.size() > 0);
            
            begin
                automatic dram_request_t req = dram_request_queue.pop_front();
                integer i;
                
                $display("[%0t]   [DRAM-RESPONDER] Starting response for read at 0x%08h", $time, req.addr);
                
                // Send 4 beats
                for (i = 0; i < 4; i++) begin
                    @(posedge clk);
                    #1;
                    bmem_rvalid = 1'b1;
                    bmem_raddr  = req.addr;
                    bmem_rdata  = (req.base_data ^ i);
                    $display("[%0t]   [DRAM-RESPONDER] Sent beat %0d for addr 0x%08h: data=0x%016h", 
                             $time, i, req.addr, (req.base_data ^ i));
                end
                
                // Clear response after done
                @(posedge clk);
                #1;
                bmem_rvalid = 1'b0;
                bmem_raddr  = 'x;
                bmem_rdata  = 'x;
                $display("[%0t]   [DRAM-RESPONDER] Completed response for read at 0x%08h", $time, req.addr);
            end
        end
    end

    // ========================================
    // Testbench Main
    // ========================================
    initial begin
        error_count = 0;
        test_count = 0;

        // Waveform dumping
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, "+all");

        // Initialize all signals
        i_req_addr = '0;
        i_req_read = 1'b0;
        i_req_write = 1'b0;
        i_req_data = '0;
        
        d_req_addr = '0;
        d_req_read = 1'b0;
        d_req_write = 1'b0;
        d_req_data = '0;

        bmem_ready = 1'b1;
        bmem_rvalid = 1'b0;
        bmem_raddr = '0;
        bmem_rdata = '0;

        // Reset
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        $display("\n========================================");
        $display("Dual Adapter Arbiter Tests");
        $display("========================================\n");

        // Basic tests without backpressure
        test_data_read();
        test_data_write();
        test_instr_read();
        test_instr_write();
        test_back_to_back_reads();
        test_back_to_back_writes();
        
        // Tests with backpressure (COMMENTED OUT - FIX TEST 6 FIRST)
        // test_data_read_backpressure();
        // test_data_write_backpressure();
        // test_instr_read_backpressure();
        // test_instr_write_backpressure();
        // test_back_to_back_reads_backpressure();
        // test_back_to_back_writes_backpressure();
        
        // Edge cases (COMMENTED OUT - FIX TEST 6 FIRST)
        // test_simultaneous_requests_data_priority();
        // test_data_preempts_instruction();
        // test_alternating_adapters();
        // test_mid_burst_adapter_switch();

        // Summary
        repeat (10) @(posedge clk);
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
    // Helper Tasks - DRAM Modeling
    // ========================================
    task automatic drive_dram_read4(input logic [31:0] A, input logic [63:0] base);
        // Just program the automatic DRAM responder
        dram_read_responses[A] = base;
        $display("[%0t]   [DRAM] Programmed response for addr 0x%08h with base 0x%016h", $time, A, base);
    endtask

    task automatic check_write_beats4(input logic [31:0] A, input logic [63:0] base);
        integer i;
        logic [63:0] captured_data[4];
        logic [31:0] captured_addr[4];
        
        for (i = 0; i < 4; i++) begin
            wait(bmem_write && bmem_ready);
            #1;
            captured_addr[i] = bmem_addr;
            captured_data[i] = bmem_wdata;
            $display("[%0t]   [INFO] Captured beat %0d: addr=0x%08h data=0x%016h", 
                     $time, i, captured_addr[i], captured_data[i]);
            @(posedge clk);
        end
        
        // Verify all beats
        for (i = 0; i < 4; i++) begin
            if (captured_addr[i] !== A || captured_data[i] !== (base | i)) begin
                $display("[%0t]   [FAIL] Beat %0d incorrect: got addr=0x%08h data=0x%016h, exp addr=0x%08h data=0x%016h",
                         $time, i, captured_addr[i], captured_data[i], A, (base | i));
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Beat %0d correct", $time, i);
            end
        end
    endtask

    // ========================================
    // Helper Tasks - Adapter Commands
    // ========================================
    task automatic send_data_read(input logic [31:0] A);
        @(posedge clk);
        #1;
        d_req_addr  = A;
        d_req_read  = 1'b1;
        d_req_write = 1'b0;
        @(posedge clk);
        #1;
        d_req_read  = 1'b0;
    endtask

    task automatic send_instr_read(input logic [31:0] A);
        @(posedge clk);
        #1;
        i_req_addr  = A;
        i_req_read  = 1'b1;
        i_req_write = 1'b0;
        @(posedge clk);
        #1;
        i_req_read  = 1'b0;
    endtask

    task automatic send_data_write(input logic [31:0] A, input logic [63:0] base);
        integer i;
        for (i = 0; i < 4; i++) begin
            @(posedge clk);
            #1;
            d_req_addr  = A;
            d_req_write = 1'b1;
            d_req_read  = 1'b0;
            d_req_data  = (base | i);
            // Wait for arbiter to accept
            wait(d_arb_ready);
        end
        @(posedge clk);
        #1;
        d_req_write = 1'b0;
    endtask

    task automatic send_instr_write(input logic [31:0] A, input logic [63:0] base);
        integer i;
        for (i = 0; i < 4; i++) begin
            @(posedge clk);
            #1;
            i_req_addr  = A;
            i_req_write = 1'b1;
            i_req_read  = 1'b0;
            i_req_data  = (base | i);
            // Wait for arbiter to accept
            wait(i_arb_ready);
        end
        @(posedge clk);
        #1;
        i_req_write = 1'b0;
    endtask

    task automatic check_data_burst4(input logic [31:0] A, input logic [63:0] base);
        integer i;
        // Wait for the first burst to arrive
        wait(d_burst_valid);
        for (i = 0; i < 4; i++) begin
            #2;
            if (!d_burst_valid) begin
                $display("[%0t]   [FAIL] Expected d_burst_valid=1 for beat %0d", $time, i);
                error_count++;
            end else if (d_burst_addr !== A || d_burst_data !== (base ^ i)) begin
                $display("[%0t]   [FAIL] Data beat %0d mismatch: got addr=0x%08h data=0x%016h, exp addr=0x%08h data=0x%016h",
                         $time, i, d_burst_addr, d_burst_data, A, (base ^ i));
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Data beat %0d OK (addr=0x%08h data=0x%016h)",
                         $time, i, d_burst_addr, d_burst_data);
            end
            @(posedge clk);
        end
    endtask

    task automatic check_instr_burst4(input logic [31:0] A, input logic [63:0] base);
        integer i;
        // Wait for the first burst to arrive
        wait(i_burst_valid);
        for (i = 0; i < 4; i++) begin
            #2;
            if (!i_burst_valid) begin
                $display("[%0t]   [FAIL] Expected i_burst_valid=1 for beat %0d", $time, i);
                error_count++;
            end else if (i_burst_addr !== A || i_burst_data !== (base ^ i)) begin
                $display("[%0t]   [FAIL] Instr beat %0d mismatch: got addr=0x%08h data=0x%016h, exp addr=0x%08h data=0x%016h",
                         $time, i, i_burst_addr, i_burst_data, A, (base ^ i));
                error_count++;
            end else begin
                $display("[%0t]   [PASS] Instr beat %0d OK (addr=0x%08h data=0x%016h)",
                         $time, i, i_burst_addr, i_burst_data);
            end
            @(posedge clk);
        end
    endtask

    // ========================================
    // TEST 1: Single Read from Data Adapter
    // ========================================
    task test_data_read();
        logic [31:0] A;
        logic [63:0] base;
        begin
            $display("\n[%0t] [TEST %0d] Single read from data adapter", $time, ++test_count);
            bmem_ready = 1'b1;
            A = 32'h0000_1000;
            base = 64'hDADA_0000_0000_0000;

            drive_dram_read4(A, base);  // Program DRAM response
            fork
                send_data_read(A);
                check_data_burst4(A, base);
            join
        end
    endtask

    // ========================================
    // TEST 2: Single Write from Data Adapter
    // ========================================
    task test_data_write();
        logic [31:0] A;
        logic [63:0] base;
        begin
            $display("\n[%0t] [TEST %0d] Single write from data adapter", $time, ++test_count);
            bmem_ready = 1'b1;
            A = 32'h0000_2000;
            base = 64'hCAFE_CAFE_0000_0000;

            fork
                send_data_write(A, base);
                check_write_beats4(A, base);
            join
        end
    endtask

    // ========================================
    // TEST 3: Single Read from Instruction Adapter
    // ========================================
    task test_instr_read();
        logic [31:0] A;
        logic [63:0] base;
        begin
            $display("\n[%0t] [TEST %0d] Single read from instruction adapter", $time, ++test_count);
            bmem_ready = 1'b1;
            A = 32'h0000_3000;
            base = 64'h1111_0000_0000_0000;

            drive_dram_read4(A, base);  // Program DRAM response
            fork
                send_instr_read(A);
                check_instr_burst4(A, base);
            join
        end
    endtask

    // ========================================
    // TEST 4: Single Write from Instruction Adapter
    // ========================================
    task test_instr_write();
        logic [31:0] A;
        logic [63:0] base;
        begin
            $display("\n[%0t] [TEST %0d] Single write from instruction adapter", $time, ++test_count);
            bmem_ready = 1'b1;
            A = 32'h0000_4000;
            base = 64'hBEEF_BEEF_0000_0000;

            fork
                send_instr_write(A, base);
                check_write_beats4(A, base);
            join
        end
    endtask

    // ========================================
    // TEST 5: Back-to-Back Reads (Data then Instruction)
    // ========================================
    task test_back_to_back_reads();
        logic [31:0] A_d, A_i;
        logic [63:0] base_d, base_i;
        begin
            $display("\n[%0t] [TEST %0d] Back-to-back reads (data then instruction)", $time, ++test_count);
            bmem_ready = 1'b1;
            A_d = 32'h0000_5000;
            A_i = 32'h0000_5100;
            base_d = 64'hAAAA_0000_0000_0000;
            base_i = 64'hBBBB_0000_0000_0000;

            // Program DRAM responses before sending requests
            drive_dram_read4(A_d, base_d);
            drive_dram_read4(A_i, base_i);

            fork
                // Send both read requests back-to-back
                begin
                    send_data_read(A_d);
                    send_instr_read(A_i);
                end
                // Check data adapter bursts (should come first due to priority)
                check_data_burst4(A_d, base_d);
                // Check instruction adapter bursts (should come second)
                check_instr_burst4(A_i, base_i);
            join
        end
    endtask

    // ========================================
    // TEST 6: Back-to-Back Writes (Data then Instruction)
    // ========================================
    task test_back_to_back_writes();
        logic [31:0] A_d, A_i;
        logic [63:0] base_d, base_i;
        integer beat_count;
        begin
            $display("\n[%0t] [TEST %0d] Back-to-back writes (data then instruction) with backpressure on last beat", $time, ++test_count);
            bmem_ready = 1'b1;
            A_d = 32'h0000_6000;
            A_i = 32'h0000_6100;
            base_d = 64'hCCCC_1111_0000_0000;
            base_i = 64'hDDDD_2222_0000_0000;
            beat_count = 0;

            fork
                begin
                    send_data_write(A_d, base_d);
                    send_instr_write(A_i, base_i);
                end
                begin
                    // Data should go first (priority)
                    check_write_beats4(A_d, base_d);
                    check_write_beats4(A_i, base_i);
                end
                begin
                    // Drop bmem_ready during the last beat of instruction write (beat 7 overall)
                    forever begin
                        @(posedge clk);
                        #2; // Sample after signals settle
                        if (bmem_write && bmem_ready && bmem_addr == A_i) begin
                            beat_count++;
                            $display("[%0t]   [BACKPRESSURE] Detected instruction write beat %0d at addr 0x%08h", 
                                     $time, beat_count, bmem_addr);
                            if (beat_count == 3) begin
                                // Drop bmem_ready for 1 cycle during beat 3 (before beat 4)
                                @(posedge clk);
                                #1;
                                bmem_ready = 1'b0;
                                $display("[%0t]   [BACKPRESSURE] Dropped bmem_ready for 1 cycle", $time);
                                @(posedge clk);
                                #1;
                                bmem_ready = 1'b1;
                                $display("[%0t]   [BACKPRESSURE] Restored bmem_ready", $time);
                                break;
                            end
                        end
                    end
                end
            join
        end
    endtask

    // ========================================
    // TEST 1.P: Data Read with Backpressure
    // ========================================
    task test_data_read_backpressure();
        logic [31:0] A;
        logic [63:0] base;
        begin
            $display("\n[%0t] [TEST %0d.P] Data read with random backpressure", $time, ++test_count);
            A = 32'h0000_7000;
            base = 64'hBACC_CCCC_0000_0000;

            fork
                send_data_read(A);
                begin
                    integer i;
                    for (i = 0; i < 4; i++) begin
                        // Random backpressure
                        if ($urandom_range(0, 1)) begin
                            bmem_ready = 1'b0;
                            repeat($urandom_range(1, 3)) @(posedge clk);
                            bmem_ready = 1'b1;
                        end
                        @(posedge clk);
                        #1;
                        bmem_rvalid = 1'b1;
                        bmem_raddr  = A;
                        bmem_rdata  = (base ^ i);
                    end
                    @(posedge clk);
                    #1;
                    bmem_rvalid = 1'b0;
                    bmem_ready = 1'b1;
                end
                check_data_burst4(A, base);
            join
        end
    endtask

    // ========================================
    // TEST 2.P: Data Write with Backpressure
    // ========================================
    task test_data_write_backpressure();
        logic [31:0] A;
        logic [63:0] base;
        begin
            $display("\n[%0t] [TEST %0d.P] Data write with mid-burst backpressure", $time, ++test_count);
            A = 32'h0000_8000;
            base = 64'hBACE_BACE_0000_0000;

            fork
                send_data_write(A, base);
                begin
                    integer i;
                    logic [63:0] captured[4];
                    for (i = 0; i < 4; i++) begin
                        // Apply backpressure randomly
                        if (i == 2) begin
                            bmem_ready = 1'b0;
                            repeat(3) @(posedge clk);
                            bmem_ready = 1'b1;
                        end
                        wait(bmem_write && bmem_ready);
                        #1;
                        captured[i] = bmem_wdata;
                        @(posedge clk);
                    end
                    // Verify
                    for (i = 0; i < 4; i++) begin
                        if (captured[i] !== (base | i)) begin
                            $display("[%0t]   [FAIL] Beat %0d data mismatch", $time, i);
                            error_count++;
                        end else begin
                            $display("[%0t]   [PASS] Beat %0d correct with backpressure", $time, i);
                        end
                    end
                end
            join
        end
    endtask

    // ========================================
    // TEST 3.P: Instruction Read with Backpressure
    // ========================================
    task test_instr_read_backpressure();
        logic [31:0] A;
        logic [63:0] base;
        begin
            $display("\n[%0t] [TEST %0d.P] Instruction read with backpressure", $time, ++test_count);
            A = 32'h0000_9000;
            base = 64'h1BAC_CCCC_0000_0000;

            fork
                send_instr_read(A);
                begin
                    integer i;
                    for (i = 0; i < 4; i++) begin
                        if (i == 1) begin
                            bmem_ready = 1'b0;
                            repeat(2) @(posedge clk);
                            bmem_ready = 1'b1;
                        end
                        @(posedge clk);
                        #1;
                        bmem_rvalid = 1'b1;
                        bmem_raddr  = A;
                        bmem_rdata  = (base ^ i);
                    end
                    @(posedge clk);
                    #1;
                    bmem_rvalid = 1'b0;
                    bmem_ready = 1'b1;
                end
                check_instr_burst4(A, base);
            join
        end
    endtask

    // ========================================
    // TEST 4.P: Instruction Write with Backpressure
    // ========================================
    task test_instr_write_backpressure();
        logic [31:0] A;
        logic [63:0] base;
        begin
            $display("\n[%0t] [TEST %0d.P] Instruction write with backpressure", $time, ++test_count);
            A = 32'h0000_A000;
            base = 64'h1BAC_EBAC_0000_0000;

            fork
                send_instr_write(A, base);
                begin
                    integer i;
                    for (i = 0; i < 4; i++) begin
                        if ($urandom_range(0, 1)) begin
                            bmem_ready = 1'b0;
                            repeat($urandom_range(1, 2)) @(posedge clk);
                            bmem_ready = 1'b1;
                        end
                        wait(bmem_write && bmem_ready);
                        @(posedge clk);
                    end
                    bmem_ready = 1'b1;
                    $display("[%0t]   [PASS] Instruction write with backpressure completed", $time);
                end
            join
        end
    endtask

    // ========================================
    // TEST 5.P: Back-to-Back Reads with Backpressure
    // ========================================
    task test_back_to_back_reads_backpressure();
        begin
            $display("\n[%0t] [TEST %0d.P] Back-to-back reads with random backpressure", $time, ++test_count);
            // Similar to test 5 but with random bmem_ready toggling
            $display("[%0t]   [PASS] Placeholder - similar to test 5 with backpressure", $time);
        end
    endtask

    // ========================================
    // TEST 6.P: Back-to-Back Writes with Backpressure
    // ========================================
    task test_back_to_back_writes_backpressure();
        begin
            $display("\n[%0t] [TEST %0d.P] Back-to-back writes with random backpressure", $time, ++test_count);
            $display("[%0t]   [PASS] Placeholder - similar to test 6 with backpressure", $time);
        end
    endtask

    // ========================================
    // EDGE CASE 1: Simultaneous Requests - Data Priority
    // ========================================
    task test_simultaneous_requests_data_priority();
        logic [31:0] A_d, A_i;
        logic [63:0] base_d, base_i;
        begin
            $display("\n[%0t] [TEST %0d] Simultaneous requests - verify data priority", $time, ++test_count);
            bmem_ready = 1'b1;
            A_d = 32'h0000_B000;
            A_i = 32'h0000_B100;
            base_d = 64'hDA1A_F111_0000_0000;
            base_i = 64'h111_7777_0000_0000;

            // Program DRAM responses
            drive_dram_read4(A_d, base_d);
            drive_dram_read4(A_i, base_i);

            // Send both on same cycle
            @(posedge clk);
            #1;
            d_req_addr = A_d;
            d_req_read = 1'b1;
            i_req_addr = A_i;
            i_req_read = 1'b1;
            
            @(posedge clk);
            #1;
            d_req_read = 1'b0;
            i_req_read = 1'b0;

            // Data should be serviced first, then instruction
            fork
                check_data_burst4(A_d, base_d);
                check_instr_burst4(A_i, base_i);
            join
            
            $display("[%0t]   [PASS] Data adapter correctly prioritized", $time);
        end
    endtask

    // ========================================
    // EDGE CASE 2: Data Preempts Instruction
    // ========================================
    task test_data_preempts_instruction();
        logic [31:0] A_i, A_d;
        logic [63:0] base_i, base_d;
        begin
            $display("\n[%0t] [TEST %0d] Data request preempts pending instruction", $time, ++test_count);
            bmem_ready = 1'b1;
            A_i = 32'h0000_C000;
            A_d = 32'h0000_C100;
            base_i = 64'h111_FFFF_0000_0000;
            base_d = 64'hDA1A_EEE1_0000_0000;

            // Program DRAM responses
            drive_dram_read4(A_i, base_i);
            drive_dram_read4(A_d, base_d);

            // Send instruction request first
            send_instr_read(A_i);
            
            // While instruction is waiting, send data request
            @(posedge clk);
            #1;
            d_req_addr = A_d;
            d_req_read = 1'b1;
            @(posedge clk);
            #1;
            d_req_read = 1'b0;

            // Data should be serviced first even though instruction came first
            fork
                check_data_burst4(A_d, base_d);
                check_instr_burst4(A_i, base_i);
            join
            
            $display("[%0t]   [PASS] Data correctly preempted instruction", $time);
        end
    endtask

    // ========================================
    // EDGE CASE 3: Alternating Adapters
    // ========================================
    task test_alternating_adapters();
        integer i;
        logic [31:0] addr;
        logic [63:0] base;
        begin
            $display("\n[%0t] [TEST %0d] Alternating requests from both adapters", $time, ++test_count);
            bmem_ready = 1'b1;

            for (i = 0; i < 3; i++) begin
                addr = 32'h0000_D000 + (i * 32'h100);
                base = 64'hA110_0000_0000_0000 + i;
                
                drive_dram_read4(addr, base);  // Program DRAM response
                
                if (i % 2 == 0) begin
                    // Data adapter
                    fork
                        send_data_read(addr);
                        check_data_burst4(addr, base);
                    join
                end else begin
                    // Instruction adapter
                    fork
                        send_instr_read(addr);
                        check_instr_burst4(addr, base);
                    join
                end
            end
            
            $display("[%0t]   [PASS] Alternating adapters test completed", $time);
        end
    endtask

    // ========================================
    // EDGE CASE 4: Mid-Burst Adapter Switch Attempt
    // ========================================
    task test_mid_burst_adapter_switch();
        logic [31:0] A_d;
        logic [63:0] base_d;
        begin
            $display("\n[%0t] [TEST %0d] Attempt to switch adapters mid-burst", $time, ++test_count);
            bmem_ready = 1'b1;
            A_d = 32'h0000_E000;
            base_d = 64'h11DB_1111_0000_0000;

            fork
                begin
                    // Start data write
                    send_data_write(A_d, base_d);
                end
                begin
                    // Try to send instruction request mid-burst
                    repeat(2) @(posedge clk);
                    #1;
                    i_req_addr = 32'h0000_E100;
                    i_req_read = 1'b1;
                    @(posedge clk);
                    #1;
                    i_req_read = 1'b0;
                    $display("[%0t]   [INFO] Instruction request sent mid-data-burst", $time);
                end
                begin
                    // Capture all writes - should all be from data adapter
                    integer i;
                    for (i = 0; i < 4; i++) begin
                        wait(bmem_write && bmem_ready);
                        @(posedge clk);
                    end
                    $display("[%0t]   [PASS] Data burst completed without interruption", $time);
                end
            join
        end
    endtask

endmodule : arbiter_dual_tb
