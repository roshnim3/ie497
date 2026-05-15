// pkt_tx FU — custom-2 instruction backend.
//
// Two instructions share one BRAM-backed TX buffer (16 words x 32 bits =
// 64 octets max, one BRAM18):
//
//   pkt_w rs1, off   — write payload word (rs1, 32b wide) to BRAM[off]
//   pkt_s rs1        — emit first rs1 octets of BRAM onto AXI-Stream
//
// Phase 1 single-buffer behavior:
//   - pkt_w writes BRAM port A in one cycle; CDB writeback fires the next
//     cycle from a registered pkt_pipe.
//   - pkt_s captures length, kicks off a state machine that issues one
//     BRAM read per cycle and drives one AXI-Stream beat per cycle (the
//     beat lags the read by one cycle due to READ_LATENCY_B=1). CDB
//     writeback fires the cycle after issue — fire-and-forget; the
//     firmware must not issue another pkt_w/pkt_s until the send drains.
//   - pkt_tx_busy keeps the RS from issuing more work mid-send.
//   - Testbench drives m_axis_pkt_tx_tready=1 always; we don't honor
//     backpressure in Phase 1.

module pkt_tx
import ooo_types::*;
(
    input  logic              clk,
    input  logic              rst,
    input  logic              flush,
    input  fu_pkt_tx_pkt      pkt,

    output logic              pkt_tx_busy,

    // AXI-Stream master to the sink (testbench or CMAC adapter)
    output logic              m_axis_tvalid,
    output logic [31:0]       m_axis_tdata,
    output logic [3:0]        m_axis_tkeep,
    output logic              m_axis_tlast,
    input  logic              m_axis_tready,  // testbench always asserts; FSM honors anyway

    output cdb_mul_div_pkt    cdb_pkt_tx
);

    // The flush port is intentionally ignored: the FSM is an externally
    // visible side effect (octets on the wire) so it cannot be rolled back,
    // and pkt_pipe stays put because pkt_w/pkt_s use rd=x0 so a stale
    // writeback can't corrupt the PRF. Reference flush here to keep the
    // signal in the netlist and suppress the unused-input lint warning.
    logic _unused_flush;
    assign _unused_flush = flush;

    // ---- TX buffer BRAM ----
    // Dual-port: port A for pkt_w writes, port B for the send-FSM reads.
    logic [31:0] bram_doutb;
    logic        port_a_we;
    logic [3:0]  port_a_addr;
    logic [31:0] port_a_data;
    logic [3:0]  read_addr_b;

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A           (4),
        .ADDR_WIDTH_B           (4),
        .AUTO_SLEEP_TIME        (0),
        .BYTE_WRITE_WIDTH_A     (32),
        .CASCADE_HEIGHT         (0),
        .CLOCKING_MODE          ("common_clock"),
        .ECC_MODE               ("no_ecc"),
        .MEMORY_INIT_FILE       ("none"),
        .MEMORY_INIT_PARAM      ("0"),
        .MEMORY_OPTIMIZATION    ("true"),
        .MEMORY_PRIMITIVE       ("block"),
        .MEMORY_SIZE            (512),      // 16 entries x 32 bits
        .MESSAGE_CONTROL        (0),
        .READ_DATA_WIDTH_B      (32),
        .READ_LATENCY_B         (1),
        .READ_RESET_VALUE_B     ("0"),
        .RST_MODE_A             ("SYNC"),
        .RST_MODE_B             ("SYNC"),
        .SIM_ASSERT_CHK         (0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT           (1),
        .USE_MEM_INIT_MMI       (0),
        .WAKEUP_TIME            ("disable_sleep"),
        .WRITE_DATA_WIDTH_A     (32),
        .WRITE_MODE_B           ("read_first"),
        .WRITE_PROTECT          (1)
    ) tx_bram_inst (
        .sleep                  (1'b0),
        .clka                   (clk),
        .ena                    (port_a_we),
        .wea                    (port_a_we),
        .addra                  (port_a_addr),
        .dina                   (port_a_data),
        .injectsbiterra         (1'b0),
        .injectdbiterra         (1'b0),
        .clkb                   (clk),
        .rstb                   (rst),
        .enb                    (1'b1),
        .regceb                 (1'b1),
        .addrb                  (read_addr_b),
        .doutb                  (bram_doutb),
        .sbiterrb               (),
        .dbiterrb               ()
    );

    // ---- FSM ----
    typedef enum logic [0:0] { TX_IDLE = 1'b0, TX_SEND = 1'b1 } tx_state_t;

    tx_state_t  state, state_n;
    logic [3:0] issue_idx, issue_idx_n;       // next BRAM port-B addr to drive
    logic [3:0] emit_idx,  emit_idx_n;        // index of the beat being driven this cycle
    logic [3:0] total_words, total_words_n;   // ceil(length_bytes / 4)
    logic [1:0] last_byte_cnt, last_byte_cnt_n;
    logic       emit_valid_q, emit_valid_n;   // 1 if this cycle drives a beat

    // Issue qualifiers (combinational, from the live pkt input)
    logic issue_pkt;
    logic issue_send;
    logic issue_write;
    assign issue_pkt   = pkt.valid && (state == TX_IDLE);
    assign issue_send  = issue_pkt &&  pkt.is_send;
    assign issue_write = issue_pkt && !pkt.is_send;

    // Length decoding for pkt_s
    logic [3:0] total_words_calc;
    logic [1:0] last_byte_cnt_calc;
    // For lengths 0..64 bytes; data[5:0] covers up to 63, data[6:0] up to 127.
    // We only care about the low 6 bits since the BRAM is 64B.
    assign total_words_calc   = (pkt.data[1:0] == 2'd0) ? pkt.data[5:2]
                                                       : (pkt.data[5:2] + 4'd1);
    assign last_byte_cnt_calc = pkt.data[1:0];

    // BRAM Port A write (combinational from pkt)
    assign port_a_we   = issue_write;
    assign port_a_addr = pkt.word_offset;
    assign port_a_data = pkt.data;

    // BRAM Port B read address
    always_comb begin
        if (state == TX_IDLE && issue_send) read_addr_b = 4'd0;
        else if (state == TX_SEND)          read_addr_b = issue_idx;
        else                                read_addr_b = 4'd0;
    end

    // ---- FSM next-state logic ----
    always_comb begin
        state_n         = state;
        issue_idx_n     = issue_idx;
        emit_idx_n      = emit_idx;
        total_words_n   = total_words;
        last_byte_cnt_n = last_byte_cnt;
        emit_valid_n    = 1'b0;

        unique case (state)
            TX_IDLE: begin
                if (issue_send) begin
                    total_words_n   = total_words_calc;
                    last_byte_cnt_n = last_byte_cnt_calc;
                    issue_idx_n     = 4'd1;
                    emit_idx_n      = 4'd0;
                    emit_valid_n    = 1'b1;
                    state_n         = TX_SEND;
                end
            end
            TX_SEND: begin
                // Honor backpressure: if the sink can't take this beat, freeze the
                // FSM (don't advance idx, keep driving the same beat). Phase 1
                // testbench always asserts tready so this is a no-op there.
                if (!m_axis_tready) begin
                    emit_valid_n = emit_valid_q;
                end else if (emit_idx == total_words - 4'd1) begin
                    state_n      = TX_IDLE;
                    emit_valid_n = 1'b0;     // last beat is THIS cycle (driven from emit_valid_q)
                end else begin
                    emit_valid_n = 1'b1;
                    issue_idx_n  = issue_idx + 4'd1;
                    emit_idx_n   = emit_idx  + 4'd1;
                end
            end
        endcase
    end

    // The TX FSM is an externally-visible side effect — once a pkt_s starts
    // emitting, octets are already on the wire, so flushing mid-send would
    // truncate the packet. Only reset clears the FSM. Speculative-start
    // protection mirrors the rationale for fetch_trade's "pop at issue":
    // pkt_s issues only after rs1 (length) is resolved, so it's typically
    // on the resolved path by the cycle it reaches the FU.
    always_ff @(posedge clk) begin
        if (rst) begin
            state         <= TX_IDLE;
            issue_idx     <= '0;
            emit_idx      <= '0;
            total_words   <= '0;
            last_byte_cnt <= '0;
            emit_valid_q  <= 1'b0;
        end else begin
            state         <= state_n;
            issue_idx     <= issue_idx_n;
            emit_idx      <= emit_idx_n;
            total_words   <= total_words_n;
            last_byte_cnt <= last_byte_cnt_n;
            emit_valid_q  <= emit_valid_n;
        end
    end

    // ---- AXI-Stream output (driven from registered state) ----
    logic is_last_beat;
    logic [3:0] tkeep_last;
    assign is_last_beat = emit_valid_q && (emit_idx == total_words - 4'd1);
    assign tkeep_last   = (last_byte_cnt == 2'd0) ? 4'b1111 :
                          (last_byte_cnt == 2'd1) ? 4'b0001 :
                          (last_byte_cnt == 2'd2) ? 4'b0011 :
                                                    4'b0111;

    assign m_axis_tvalid = emit_valid_q;
    assign m_axis_tdata  = bram_doutb;
    assign m_axis_tlast  = is_last_beat;
    assign m_axis_tkeep  = is_last_beat ? tkeep_last : 4'b1111;

    // Tell the RS we're mid-send and can't accept anything new. Must be a
    // pure register read — if it depended on state_n it would close a
    // combinational loop through the RS's stall input. The single-cycle gap
    // (RS dequeues at the same rising edge state transitions to SEND) is
    // fine because the RS only issues one entry per cycle anyway.
    assign pkt_tx_busy = (state == TX_SEND);

    // ---- CDB writeback (1-cycle delayed from issue) ----
    // Both pkt_w and pkt_s writeback rd=0 (instructions always use x0 in the
    // macros). The writeback exists so the ROB can retire the instruction.
    // pkt_pipe holds the input for one cycle so cdb_pkt_tx can fire from a
    // registered packet. We don't flush it on flush: the firmware uses rd=x0
    // (see the PKT_W / PKT_S macros), so a stale writeback can't corrupt the
    // PRF or wake spurious RS entries. Preserving the writeback also keeps
    // the ROB from deadlocking when pkt_s is on the resolved path but a
    // later mispredict (e.g., _fini's loop branch) flushes the pipeline.
    fu_pkt_tx_pkt pkt_pipe;
    always_ff @(posedge clk) begin
        if (rst) begin
            pkt_pipe <= '0;
        end else begin
            pkt_pipe <= '0;
            if (issue_pkt) begin
                pkt_pipe <= pkt;
            end
        end
    end

    always_comb begin
        cdb_pkt_tx = '{default: '0};
        if (pkt_pipe.valid) begin
            cdb_pkt_tx.valid     = 1'b1;
            cdb_pkt_tx.result    = 32'd0;
            cdb_pkt_tx.rob_index = pkt_pipe.rob_index;
            cdb_pkt_tx.rd_paddr  = pkt_pipe.rd_paddr;
            cdb_pkt_tx.rd_addr   = pkt_pipe.rd_addr;
            // RVFI shadow expects the rs1 value the CPU actually read. Both
            // pkt_w and pkt_s take rs1 (carried in pkt.data) and no rs2.
            cdb_pkt_tx.rs1_val   = pkt_pipe.data;
            cdb_pkt_tx.rs2_val   = 32'd0;
        end
    end

endmodule : pkt_tx
