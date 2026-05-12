module decode_rename_tb;

    timeunit 1ps;
    timeprecision 1ps;

    //---------------------------------------------------------------------------------
    // Clock and Reset
    //---------------------------------------------------------------------------------
    int clock_half_period_ps = 5000; // 10ns period = 100MHz
    
    bit clk;
    always #(clock_half_period_ps) clk = ~clk;
    bit rst;

    //---------------------------------------------------------------------------------
    // Memory interface (banked burst interface for DRAM)
    //---------------------------------------------------------------------------------
    mem_itf_banked mem_itf(.*);
    dram_w_burst_frfcfs_controller mem(.itf(mem_itf));

    //---------------------------------------------------------------------------------
    // Instantiate the DUT (CPU)
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
    // Waveform generation
    //---------------------------------------------------------------------------------
    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, "+all");
    end

    //---------------------------------------------------------------------------------
    // Main test sequence
    //---------------------------------------------------------------------------------
    initial begin
        // Display test header
        $display("========================================");
        $display("Decode and Rename Stage Test");
        $display("========================================\n");
        $display("Testing decode and rename pipeline stages");
        $display("This test will run for several cycles to observe pipeline behavior\n");

        // Reset sequence
        rst = 1'b1;
        repeat(10) @(posedge clk);
        rst = 1'b0;
        $display("[%0t] Reset complete, starting operation", $time);
        
        // Run for a number of cycles to let instructions flow through
        // Fetch -> Decode -> Rename
        repeat(200) @(posedge clk);
        
        $display("\n========================================");
        $display("Test Complete");
        $display("========================================");
        $display("Check the waveform dump to analyze:");
        $display("  - Fetch stage output (fetch_packet)");
        $display("  - Decode stage output (decode_packet)");
        $display("  - Rename stage output (rename_pkt)");
        $display("  - RAT entries (rat_out)");
        $display("  - Freelist status (freelist_empty, freelist_full)");
        $display("  - Physical register allocation (alloc_reg, alloc_valid)");
        $display("========================================\n");

        $finish;
    end

    //---------------------------------------------------------------------------------
    // Monitor - Display key signals during operation
    //---------------------------------------------------------------------------------
    
    // Monitor fetch packet
    always @(posedge clk) begin
        if (!rst && dut.fetch_packet.fields.valid) begin
            $display("[%0t] FETCH: valid=1, PC=0x%h, inst=0x%h", 
                    $time, dut.fetch_packet.fields.pc, dut.fetch_packet.fields.inst);
        end
    end
    
    // Monitor decode packet
    always @(posedge clk) begin
        if (!rst && dut.decode_packet.valid) begin
            $display("[%0t] DECODE: valid=1, PC=0x%h, inst=0x%h, rd=%0d, rs1=%0d, rs2=%0d, fu_flag=%s", 
                    $time, dut.decode_packet.pc, dut.decode_packet.inst,
                    dut.decode_packet.rd_addr, dut.decode_packet.rs1_addr, dut.decode_packet.rs2_addr,
                    dut.decode_packet.fu_flag.name());
        end
    end
    
    // Monitor rename packet
    always @(posedge clk) begin
        if (!rst && dut.rename_pkt.valid) begin
            $display("[%0t] RENAME: valid=1, PC=0x%h, inst=0x%h, rd_paddr=P%0d, rs1_paddr=P%0d, rs2_paddr=P%0d", 
                    $time, dut.rename_pkt.pc, dut.rename_pkt.inst,
                    dut.rename_pkt.rd_paddr, dut.rename_pkt.rs1_paddr, dut.rename_pkt.rs2_paddr);
        end
    end
    
    // Monitor physical register allocation
    always @(posedge clk) begin
        if (!rst && dut.alloc_valid) begin
            $display("[%0t] FREELIST: Allocated physical register P%0d", 
                    $time, dut.alloc_reg);
        end
    end
    
    // Monitor freelist status changes
    logic prev_empty, prev_full;
    always @(posedge clk) begin
        if (!rst) begin
            if (dut.freelist_empty && !prev_empty) begin
                $display("[%0t] WARNING: Freelist is now EMPTY", $time);
            end
            if (dut.freelist_full && !prev_full) begin
                $display("[%0t] WARNING: Freelist is now FULL", $time);
            end
            prev_empty = dut.freelist_empty;
            prev_full = dut.freelist_full;
        end
    end
    
    // Monitor RAT writes
    always @(posedge clk) begin
        if (!rst && dut.rat_wen) begin
            $display("[%0t] RAT: Writing R%0d -> P%0d (ready=%0b, valid=%0b)", 
                    $time, dut.rat_waddr, dut.rat_wdata.phys_reg, 
                    dut.rat_wdata.ready, dut.rat_wdata.valid);
        end
    end

endmodule
