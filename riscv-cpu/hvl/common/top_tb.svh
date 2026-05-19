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

    // pkt_tx AXI-Stream master from the CPU
    logic        pkt_tx_tvalid;
    logic [31:0] pkt_tx_tdata;
    logic [3:0]  pkt_tx_tkeep;
    logic        pkt_tx_tlast;
    logic        pkt_tx_tready;

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
        .parser_commit (parser_commit),

        .m_axis_pkt_tx_tvalid (pkt_tx_tvalid),
        .m_axis_pkt_tx_tdata  (pkt_tx_tdata),
        .m_axis_pkt_tx_tkeep  (pkt_tx_tkeep),
        .m_axis_pkt_tx_tlast  (pkt_tx_tlast),
        .m_axis_pkt_tx_tready (pkt_tx_tready)
    );

    fake_packet_sink pkt_tx_sink (
        .clk    (clk),
        .rst    (rst),
        .tvalid (pkt_tx_tvalid),
        .tdata  (pkt_tx_tdata),
        .tkeep  (pkt_tx_tkeep),
        .tlast  (pkt_tx_tlast),
        .tready (pkt_tx_tready)
    );

    // Concurrent-staging-vs-send counters. *_cycles increments any cycle
    // the FU's BRAM Port A write fires while the FSM is also driving an
    // AXI-Stream beat (Port B read). >0 proves staging and send genuinely
    // overlap. The separate counts are sanity for what each side actually
    // saw.
    int pkt_tx_overlap_cycles;
    int pkt_tx_writes;
    int pkt_tx_emits;
    always @(posedge clk) begin
        if (rst) begin
            pkt_tx_overlap_cycles <= 0;
            pkt_tx_writes         <= 0;
            pkt_tx_emits          <= 0;
        end else begin
            if (dut.pkt_tx_unit.port_a_we && dut.pkt_tx_unit.emit_valid_q) begin
                pkt_tx_overlap_cycles <= pkt_tx_overlap_cycles + 1;
            end
            if (dut.pkt_tx_unit.port_a_we)    pkt_tx_writes <= pkt_tx_writes + 1;
            if (dut.pkt_tx_unit.emit_valid_q) pkt_tx_emits  <= pkt_tx_emits + 1;
        end
    end

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

    // ---- Tick-to-trade per-packet TX timestamping ----
    // tx_first_beat_ts[K] stamps the cycle the K-th emitted frame's first
    // AXI-Stream beat fires. tx_parser_idx[K] = commit_idx at that moment,
    // which is the index into write_ts[] for the parser packet that fed
    // the decision (the firmware processes parser packets in FIFO order
    // and emits PACKET_DONE per iteration, so commit_idx at TX time names
    // the parser packet currently being processed).
    //
    // itch_tick_to_trade.c drops the FU's preloaded slot before the metric
    // loop, so iteration K of the loop matches parser commit K.
    longint tx_first_beat_ts [LATENCY_LOG_SIZE];
    int     tx_parser_idx    [LATENCY_LOG_SIZE];
    int     tx_idx;
    logic   tx_in_packet;

    initial begin
        tx_idx       = 0;
        tx_in_packet = 1'b0;
        for (int i = 0; i < LATENCY_LOG_SIZE; i++) begin
            tx_first_beat_ts[i] = -64'sd1;
            tx_parser_idx[i]    = -1;
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            if (pkt_tx_tvalid && pkt_tx_tready) begin
                if (!tx_in_packet && tx_idx < LATENCY_LOG_SIZE) begin
                    tx_first_beat_ts[tx_idx] <= cycle_count;
                    tx_parser_idx[tx_idx]    <= commit_idx;
                    tx_idx                   <= tx_idx + 1;
                end
                // tx_in_packet stays 1 mid-frame; clears the cycle after tlast.
                tx_in_packet <= !pkt_tx_tlast;
            end
        end
    end

    // ---- Tick-to-trade waterfall ----
    // Per-iteration timestamps, indexed by commit_idx at PACKET_DONE
    // commit time. Each row in tick_to_trade_breakdown.csv is one
    // accepted iteration; we skip iterations with no TX event (warmup or
    // rejected). Events go into a pending buffer that resets on each
    // parser_commit pulse (start of a new iteration window) and is
    // finalized into the slot when that iteration's PACKET_DONE commits.
    // Using cdb_trade.valid (instead of rs_ft_enq.valid) for the FT
    // signals avoids attributing speculatively-dispatched-then-flushed
    // FT instructions — cdb_trade only fires for completions.
    longint t_ft_dispatch    [LATENCY_LOG_SIZE];  // first cdb_trade.valid after parser_commit
    longint t_ft_commit      [LATENCY_LOG_SIZE];  // last cdb_trade.valid in iter
    longint t_pkts_dispatch  [LATENCY_LOG_SIZE];  // first pkt_s entry into pkt_tx_rs
    longint t_pkts_fsm_start [LATENCY_LOG_SIZE];  // FSM IDLE->SEND (last cycle in IDLE)
    longint t_tx_first_beat  [LATENCY_LOG_SIZE];  // first AXI-Stream beat
    longint t_tx_last_beat   [LATENCY_LOG_SIZE];  // tlast

    longint pending_t_ft_dispatch;
    longint pending_t_ft_commit;
    longint pending_t_pkts_dispatch;
    longint pending_t_pkts_fsm_start;
    longint pending_t_tx_first_beat;

    // tlast fires AFTER iter K's PACKET_DONE commits (the FSM drains in
    // parallel with the next iter's processing), so it can't go through
    // the pending+finalize path. Capture it directly using the iter index
    // saved at first-beat time.
    logic   tx_active;
    int     tx_active_iter;

    initial begin
        for (int i = 0; i < LATENCY_LOG_SIZE; i++) begin
            t_ft_dispatch[i]    = -64'sd1;
            t_ft_commit[i]      = -64'sd1;
            t_pkts_dispatch[i]  = -64'sd1;
            t_pkts_fsm_start[i] = -64'sd1;
            t_tx_first_beat[i]  = -64'sd1;
            t_tx_last_beat[i]   = -64'sd1;
        end
        pending_t_ft_dispatch    = -64'sd1;
        pending_t_ft_commit      = -64'sd1;
        pending_t_pkts_dispatch  = -64'sd1;
        pending_t_pkts_fsm_start = -64'sd1;
        pending_t_tx_first_beat  = -64'sd1;
        tx_active                = 1'b0;
        tx_active_iter           = 0;
    end

    // Capture into pending buffer, reset on parser_commit, finalize on
    // PACKET_DONE commit. NBA read order means a finalize on the same
    // cycle as a parser_commit reads the pre-reset pending values.
    always @(posedge clk) begin
        if (!rst) begin
            if (fake_parser.commit) begin
                pending_t_ft_dispatch    <= -64'sd1;
                pending_t_ft_commit      <= -64'sd1;
                pending_t_pkts_dispatch  <= -64'sd1;
                pending_t_pkts_fsm_start <= -64'sd1;
                pending_t_tx_first_beat  <= -64'sd1;
            end else begin
                if (dut.cdb_trade.valid) begin
                    if (pending_t_ft_dispatch == -64'sd1)
                        pending_t_ft_dispatch <= cycle_count;
                    // Only update ft_commit while pkt_s hasn't dispatched
                    // yet — keeps the pop's cdb_trade (slot 5) from
                    // overwriting the price read's commit.
                    if (pending_t_pkts_dispatch == -64'sd1)
                        pending_t_ft_commit <= cycle_count;
                end
                if (dut.rs_pt_enq.valid && dut.rs_pt_enq.is_send
                    && pending_t_pkts_dispatch == -64'sd1) begin
                    pending_t_pkts_dispatch <= cycle_count;
                end
                if (dut.pkt_tx_unit.state == 1'b0 && dut.pkt_tx_unit.state_n == 1'b1
                    && pending_t_pkts_fsm_start == -64'sd1) begin
                    pending_t_pkts_fsm_start <= cycle_count;
                end
                if (pkt_tx_tvalid && pkt_tx_tready
                    && pending_t_tx_first_beat == -64'sd1) begin
                    pending_t_tx_first_beat <= cycle_count;
                end
            end

            // Finalize on PACKET_DONE commit (commit_idx read here is the
            // pre-increment value = iteration index).
            if (dut.commit[0] && dut.rob_head_entry[0].inst == PACKET_DONE_MARKER
                && commit_idx < LATENCY_LOG_SIZE) begin
                t_ft_dispatch[commit_idx]    <= pending_t_ft_dispatch;
                t_ft_commit[commit_idx]      <= pending_t_ft_commit;
                t_pkts_dispatch[commit_idx]  <= pending_t_pkts_dispatch;
                t_pkts_fsm_start[commit_idx] <= pending_t_pkts_fsm_start;
                t_tx_first_beat[commit_idx]  <= pending_t_tx_first_beat;
            end
            if (dut.commit[1] && dut.rob_head_entry[1].inst == PACKET_DONE_MARKER
                && commit_idx < LATENCY_LOG_SIZE) begin
                t_ft_dispatch[commit_idx]    <= pending_t_ft_dispatch;
                t_ft_commit[commit_idx]      <= pending_t_ft_commit;
                t_pkts_dispatch[commit_idx]  <= pending_t_pkts_dispatch;
                t_pkts_fsm_start[commit_idx] <= pending_t_pkts_fsm_start;
                t_tx_first_beat[commit_idx]  <= pending_t_tx_first_beat;
            end

            // tlast capture — uses the iter index claimed at first beat.
            if (pkt_tx_tvalid && pkt_tx_tready) begin
                if (!tx_active && commit_idx < LATENCY_LOG_SIZE) begin
                    tx_active_iter <= commit_idx;
                    tx_active      <= 1'b1;
                end
                if (pkt_tx_tlast && tx_active_iter < LATENCY_LOG_SIZE) begin
                    t_tx_last_beat[tx_active_iter] <= cycle_count;
                    tx_active                      <= 1'b0;
                end
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

    // Drain delay — give the pkt_tx AXI-Stream a window to finish a send in
    // flight when the firmware's halt marker commits before the last beat
    // leaves the FU. Counts down only while idle so we don't fire mid-burst.
    int pkt_tx_drain_cycles;
    initial pkt_tx_drain_cycles = 32;

    always @(posedge clk) begin
        if (mon_itf.halt && pkt_tx_drain_cycles > 0) begin
            if (pkt_tx_tvalid) begin
                pkt_tx_drain_cycles <= 32;       // reset window each beat
            end else begin
                pkt_tx_drain_cycles <= pkt_tx_drain_cycles - 1;
            end
        end
    end

    always @(posedge clk) begin
        if (mon_itf.halt && pkt_tx_drain_cycles == 0) begin
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
            $display("[pkt_tx] writes=%0d emits=%0d overlap=%0d",
                     pkt_tx_writes, pkt_tx_emits, pkt_tx_overlap_cycles);
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

            // Tick-to-trade latency: parser commit -> first TX beat for
            // every emitted (accepted) packet. Skip rows where the parser
            // idx falls outside write_ts[] (preloaded packet — shouldn't
            // hit with itch_tick_to_trade.c, defensive only).
            if (parser_enable && tx_idx > 0) begin
                int fd_tt;
                int dumped;
                fd_tt  = $fopen("tick_to_trade_latency.csv", "w");
                dumped = 0;
                $fdisplay(fd_tt, "accept_idx,parser_commit_cycle,tx_first_beat_cycle,latency_cycles");
                for (int i = 0; i < tx_idx; i++) begin
                    if (tx_parser_idx[i] >= 0 && tx_parser_idx[i] < write_idx) begin
                        $fdisplay(fd_tt, "%0d,%0d,%0d,%0d",
                                  i,
                                  write_ts[tx_parser_idx[i]],
                                  tx_first_beat_ts[i],
                                  tx_first_beat_ts[i] - write_ts[tx_parser_idx[i]]);
                        dumped++;
                    end
                end
                $fclose(fd_tt);
                $display("Tick-to-trade: %0d accepted frames logged to tick_to_trade_latency.csv (tx_idx=%0d)",
                         dumped, tx_idx);
            end

            // Full waterfall: one row per accepted iteration, with all
            // 7 timestamps + the canonical deltas. Skip iterations that
            // had no TX event (warmup or rejected).
            if (parser_enable && tx_idx > 0) begin
                int     fd_br;
                int     br_accept_idx;
                int     n_iters;
                int     k_br;
                longint pc, fd_, fc, pd, fs, fb, lb;
                fd_br         = $fopen("tick_to_trade_breakdown.csv", "w");
                br_accept_idx = 0;
                n_iters       = (commit_idx < LATENCY_LOG_SIZE) ? commit_idx : LATENCY_LOG_SIZE;
                $fdisplay(fd_br, "accept_idx,parser_idx,t_parser_commit,t_ft_dispatch,t_ft_commit,t_pkts_dispatch,t_pkts_fsm_start,t_tx_first_beat,t_tx_last_beat,rx_wait,decision,tx_issue,tx_drain,total");
                for (k_br = 0; k_br < n_iters; k_br++) begin
                    if (t_tx_first_beat[k_br] >= 0 && k_br < write_idx) begin
                        pc  = write_ts[k_br];
                        fd_ = t_ft_dispatch[k_br];
                        fc  = t_ft_commit[k_br];
                        pd  = t_pkts_dispatch[k_br];
                        fs  = t_pkts_fsm_start[k_br];
                        fb  = t_tx_first_beat[k_br];
                        lb  = t_tx_last_beat[k_br];
                        $fdisplay(fd_br, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                                  br_accept_idx,
                                  k_br,
                                  pc, fd_, fc, pd, fs, fb, lb,
                                  fd_ - pc,        // rx_wait
                                  pd  - fc,        // decision
                                  fs  - pd,        // tx_issue
                                  lb  - fb + 1,    // tx_drain (beats)
                                  lb  - pc);       // total
                        br_accept_idx++;
                    end
                end
                $fclose(fd_br);
                $display("Tick-to-trade waterfall: %0d rows logged to tick_to_trade_breakdown.csv",
                         br_accept_idx);
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
