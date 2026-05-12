    longint timeout;
    initial begin
        $value$plusargs("TIMEOUT_ECE411=%d", timeout);
    end

    mem_itf_banked mem_itf(.*);
    dram_w_burst_frfcfs_controller mem(.itf(mem_itf));

    mon_itf #(.CHANNELS(8)) mon_itf(.*);
    monitor #(.CHANNELS(8)) monitor(.itf(mon_itf));

    cpu dut(
        .clk            (clk),
        .rst            (rst),

        .bmem_addr  (mem_itf.addr  ),
        .bmem_read  (mem_itf.read  ),
        .bmem_write (mem_itf.write ),
        .bmem_wdata (mem_itf.wdata ),
        .bmem_ready (mem_itf.ready ),
        .bmem_raddr (mem_itf.raddr ),
        .bmem_rdata (mem_itf.rdata ),
        .bmem_rvalid(mem_itf.rvalid)
    );

    `include "rvfi_reference.svh"

    // Branch Prediction Accuracy Monitor
    int total_branches = 0;
    int mispredictions = 0;
    int total_commits = 0;

    always @(posedge clk) begin
        if (!rst) begin
            // Count mispredictions: any flush indicates a branch misprediction
            if (dut.flush[0]) begin
                mispredictions++;
            end
            if (dut.flush[1]) begin
                mispredictions++;
            end
            
            // Count total branches: track branches as they execute in the branch unit
            // cdb_br.valid means a branch finished execution
            if (dut.cdb_br.valid) begin
                total_branches++;
            end
            
            // Also track total commits for context
            if (dut.commit[0]) total_commits++;
            if (dut.commit[1]) total_commits++;
        end
    end

    always @(posedge clk) begin
        if (mon_itf.halt) begin
            // Print BP accuracy stats before finishing
            real bp_accuracy;
            if (total_branches > 0) begin
                bp_accuracy = 100.0 * (1.0 - (real'(mispredictions) / real'(total_branches)));
                $display("====================================");
                $display("Branch Prediction Statistics:");
                $display("  Total Branches:    %0d", total_branches);
                $display("  Mispredictions:    %0d", mispredictions);
                $display("  BP Accuracy:       %.2f%%", bp_accuracy);
                $display("  Total Commits:     %0d", total_commits);
                $display("====================================");
            end
            $finish;
        end
        if (timeout == 0) begin
            $error("TB Error: Timed out");
            $fatal;
        end
        if (mem_itf.error != 0 || mon_itf.error != 0) begin
            $fatal;
        end
        timeout <= timeout - 1;
    end
