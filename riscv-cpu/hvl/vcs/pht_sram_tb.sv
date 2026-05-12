module pht_sram_tb;

    logic clk;
    logic rst;

    // SRAM signals
    logic       csb;
    logic       web;
    logic [7:0] addr;
    logic [1:0] din;
    logic [1:0] dout;

    // Instantiate the PHT SRAM
    bp_pht pht (
        .clk0  (clk),
        .csb0  (csb),
        .web0  (web),
        .addr0 (addr),
        .din0  (din),
        .dout0 (dout)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test sequence
    initial begin
        $display("=== PHT SRAM Test ===");
        
        // Initialize signals
        rst = 1;
        web = 1;  // read mode
        addr = 8'h00;
        din = 2'b00;
        
        // Reset
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        
        $display("Test 1: Write 2'b10 to address 0x00");
        @(posedge clk);
        csb = 0;   // enable
        web = 1;   // write mode
        addr = 8'h00;
        din = 2'b10;
        @(posedge clk);
        $display("  dout = %b RANDNDNDN", dout);

        $display("Test 2: Read from address 0x00 (should be 2'b10)");
        @(posedge clk);
        web = 1;   // read mode
        addr = 8'h00;
        @(posedge clk);
        @(posedge clk);
        $display("  dout = %b (expected 2'b10)", dout);
        
        $display("Test 3: Write 2'b01 to address 0x0F");
        @(posedge clk);
        web = 0;   // write mode
        addr = 8'h0F;
        din = 2'b01;
        
        $display("Test 4: Read from address 0x0F (should be 2'b01)");
        @(posedge clk);
        web = 1;   // read mode
        addr = 8'h0F;
        @(posedge clk);
        @(posedge clk);
        $display("  dout = %b (expected 2'b01)", dout);
        
        $display("Test 5: Write 2'b11 to address 0xFF");
        @(posedge clk);
        web = 0;   // write mode
        addr = 8'hFF;
        din = 2'b11;
        
        $display("Test 6: Read from address 0xFF (should be 2'b11)");
        @(posedge clk);
        web = 1;   // read mode
        addr = 8'hFF;
        @(posedge clk);
        @(posedge clk);
        $display("  dout = %b (expected 2'b11)", dout);
        
        $display("Test 7: Read from address 0x00 again (should still be 2'b10)");
        @(posedge clk);
        addr = 8'h00;
        @(posedge clk);
        @(posedge clk);
        $display("  dout = %b (expected 2'b10)", dout);
        
        $display("Test 8: Check random initialized values");
        @(posedge clk);
        addr = 8'h55;
        @(posedge clk);
        @(posedge clk);
        $display("  dout at 0x55 = %b (random init value)", dout);
        
        @(posedge clk);
        addr = 8'hAA;
        @(posedge clk);
        @(posedge clk);
        $display("  dout at 0xAA = %b (random init value)", dout);
        
        @(posedge clk);
        @(posedge clk);
        $display("=== Test Complete ===");
        $finish;
    end

    // Monitor for debugging
    initial begin
        $monitor("Time=%0t clk=%b rst=%b csb=%b web=%b addr=%h din=%b dout=%b", 
                 $time, clk, rst, csb, web, addr, din, dout);
    end

    // Dump waveforms
    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, "+all");
    end

endmodule
