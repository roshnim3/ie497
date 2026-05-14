    longint timeout;
    initial begin
        $value$plusargs("TIMEOUT_ECE411=%d", timeout);
    end

    mem_itf_banked mem_itf(.*);
    dram_w_burst_frfcfs_controller mem(.itf(mem_itf));

    mon_itf #(.CHANNELS(8)) mon_itf(.*);
    monitor #(.CHANNELS(8)) monitor(.itf(mon_itf));

    // Parser write port for the fetch_trade BRAM. Off by default for
    // existing benchmarks; the fake_packet_parser drives these when the
    // streaming benchmark is run with +PARSER_ENABLE_ECE411=1.
    logic        parser_we;
    logic [2:0]  parser_addr;
    logic [31:0] parser_data;
    logic        parser_commit;

    logic        parser_enable;
    logic [31:0] parser_interval;   // cycles between packets
    initial begin
        parser_enable   = 1'b0;
        parser_interval = 32'd16;
        $value$plusargs("PARSER_ENABLE_ECE411=%d",   parser_enable);
        $value$plusargs("PARSER_INTERVAL_ECE411=%d", parser_interval);
    end

    logic        fp_we;
    logic [2:0]  fp_addr;
    logic [31:0] fp_data;
    logic        fp_commit;
    fake_packet_parser fake_parser (
        .clk      (clk),
        .rst      (rst),
        .enable   (parser_enable),
        .interval (parser_interval),
        .we       (fp_we),
        .addr     (fp_addr),
        .data     (fp_data),
        .commit   (fp_commit)
    );

    assign parser_we     = parser_enable ? fp_we     : 1'b0;
    assign parser_addr   = parser_enable ? fp_addr   : 3'b0;
    assign parser_data   = parser_enable ? fp_data   : 32'b0;
    assign parser_commit = parser_enable ? fp_commit : 1'b0;

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
        .bmem_rvalid(mem_itf.rvalid),

        .parser_we     (parser_we),
        .parser_addr   (parser_addr),
        .parser_data   (parser_data),
        .parser_commit (parser_commit)
    );

    // ---- Latency-histogram instrumentation ----
    // Firmware emits `slti x0, x0, 7` after processing each packet.
    // Encoded: imm=7, rs1=0, funct3=010, rd=0, opcode=0010011 -> 0x00702013.
    localparam logic [31:0] PACKET_DONE_MARKER = 32'h00702013;
    localparam int LATENCY_LOG_SIZE = 4096;

    longint write_ts  [LATENCY_LOG_SIZE];
    longint commit_ts [LATENCY_LOG_SIZE];
    int     write_idx;
    int     commit_idx;
    longint cycle_count;

    initial begin
        write_idx   = 0;
        commit_idx  = 0;
        cycle_count = 64'd0;
        for (int i = 0; i < LATENCY_LOG_SIZE; i++) begin
            write_ts[i]  = -64'sd1;
            commit_ts[i] = -64'sd1;
        end
    end

    always @(posedge clk) if (!rst) cycle_count <= cycle_count + 64'd1;

    // Record parser write times (one per new packet, on the seq slot 3 write)
    always @(posedge clk) begin
        if (!rst && fake_parser.commit && write_idx < LATENCY_LOG_SIZE) begin
            write_ts[write_idx] <= cycle_count;
            write_idx           <= write_idx + 1;
        end
    end

    // Record firmware completion times (one per slti-7 commit)
    always @(posedge clk) begin
        if (!rst) begin
            if (dut.commit[0] && dut.rob_head_entry[0].inst == PACKET_DONE_MARKER
                && commit_idx < LATENCY_LOG_SIZE) begin
                commit_ts[commit_idx] <= cycle_count;
                commit_idx            <= commit_idx + 1;
            end
            if (dut.commit[1] && dut.rob_head_entry[1].inst == PACKET_DONE_MARKER
                && commit_idx < LATENCY_LOG_SIZE) begin
                commit_ts[commit_idx] <= cycle_count;
                commit_idx            <= commit_idx + 1;
            end
        end
    end

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
            // Dump latency histogram if streaming mode produced data.
            if (parser_enable && write_idx > 0) begin
                int fd;
                int n;
                fd = $fopen("latency.csv", "w");
                n  = (write_idx < commit_idx) ? write_idx : commit_idx;
                $fdisplay(fd, "packet_idx,write_cycle,commit_cycle,latency_cycles");
                for (int i = 0; i < n; i++) begin
                    $fdisplay(fd, "%0d,%0d,%0d,%0d",
                              i, write_ts[i], commit_ts[i],
                              commit_ts[i] - write_ts[i]);
                end
                $fclose(fd);
                $display("Latency histogram: %0d packets logged to latency.csv", n);
                $display("  write_idx=%0d commit_idx=%0d", write_idx, commit_idx);
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
