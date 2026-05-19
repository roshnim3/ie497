// pkt_tx FU — custom-2 instruction backend, Phase 2 multi-buffer.
//
// Two instructions share a BRAM-backed TX buffer of 8 packets x 16 words x
// 32b each (4 Kibit, one BRAM18):
//
//   pkt_w rs1, off   — write payload word (rs1, 32b wide) to staging slot
//                       at word offset off (0..15)
//   pkt_s rs1        — commit the staging slot: record length=rs1 octets
//                       and advance staging_ptr so the drain FSM can pick
//                       it up
//
// Multi-buffer FIFO discipline mirrors the RX fetch_trade design, inverted:
//   - staging_ptr (CPU side, producer): the slot currently being filled.
//     pkt_w writes BRAM Port A at {staging_ptr_low, off}. pkt_s records
//     pkt_length[staging_ptr_low] = rs1 and bumps staging_ptr.
//   - send_ptr (HW side, consumer): the slot the drain FSM is emitting from.
//     The FSM is independent of the FU input; it polls staging_ptr vs
//     send_ptr and starts a new drain whenever the FIFO is non-empty.
//   - 4-entry pointers: MSB is the wrap flag, low 3 select the slot.
//     fifo_empty when staging == send, fifo_full when wraps differ and
//     low bits match (8 in-flight slots).
//
// Phase 2 lets the CPU pipeline a new packet (pkt_w stream into staging
// slot K+1) while the HW is still draining slot K — Port A writes at addr
// {K+1, off}, Port B reads at addr {K, idx}, so the dual-port BRAM serves
// both with no conflict. The RS only stalls when the FIFO is genuinely
// full (no remaining staging slot).
//
// CDB writeback for both pkt_w and pkt_s fires one cycle after issue from
// a registered pkt_pipe. Both use rd=x0 in the firmware macros, so a stale
// writeback (e.g., after a flush) can't corrupt the PRF. The drain FSM is
// not flushable: once octets are on the wire they can't be rolled back.
// Speculative-start protection mirrors fetch_trade's "pop at issue" — by
// the cycle pkt_s reaches the FU, rs1 is resolved and the instruction is
// effectively on the resolved path.

module pkt_tx
import ooo_types::*;
(
    input  logic              clk,
    input  logic              rst,
    input  logic              flush,
    input  fu_pkt_tx_pkt      pkt,

    output logic              pkt_tx_busy,    // FIFO full — RS must stall

    // AXI-Stream master to the sink (testbench or CMAC adapter)
    output logic              m_axis_tvalid,
    output logic [31:0]       m_axis_tdata,
    output logic [3:0]        m_axis_tkeep,
    output logic              m_axis_tlast,
    input  logic              m_axis_tready,  // testbench always asserts; FSM honors anyway

    output cdb_mul_div_pkt    cdb_pkt_tx
);

    // The flush port is intentionally ignored: the drain FSM is an externally
    // visible side effect (octets on the wire), and pkt_pipe stays put
    // because pkt_w/pkt_s use rd=x0 so a stale writeback can't corrupt the
    // PRF. Reference flush in a dummy signal to keep it in the netlist and
    // silence the unused-input lint.
    logic _unused_flush;
    assign _unused_flush = flush;

    // ---- FIFO pointers ----
    localparam BUF_DEPTH      = 8;
    localparam BUF_DEPTH_BITS = 3;   // log2(BUF_DEPTH)

    // 4 entries wide: MSB is wrap, low 3 select the slot.
    logic [BUF_DEPTH_BITS:0] staging_ptr;
    logic [BUF_DEPTH_BITS:0] send_ptr;

    logic fifo_empty;
    logic fifo_full;
    assign fifo_empty = (staging_ptr == send_ptr);
    assign fifo_full  = (staging_ptr[BUF_DEPTH_BITS] != send_ptr[BUF_DEPTH_BITS]) &&
                        (staging_ptr[BUF_DEPTH_BITS-1:0] == send_ptr[BUF_DEPTH_BITS-1:0]);

    // Per-slot length (in octets) recorded by pkt_s, consumed by the FSM
    // when it starts draining a slot. Small distributed-RAM array.
    logic [6:0] pkt_length [BUF_DEPTH];

    // ---- TX buffer BRAM ----
    // Dual-port: Port A for pkt_w writes (staging_ptr_low | word_offset),
    // Port B for the drain FSM (send_ptr_low | issue_idx).
    logic [31:0] bram_doutb;
    logic        port_a_we;
    logic [6:0]  port_a_addr;
    logic [31:0] port_a_data;
    logic [6:0]  read_addr_b;

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A           (7),
        .ADDR_WIDTH_B           (7),
        .AUTO_SLEEP_TIME        (0),
        .BYTE_WRITE_WIDTH_A     (32),
        .CASCADE_HEIGHT         (0),
        .CLOCKING_MODE          ("common_clock"),
        .ECC_MODE               ("no_ecc"),
        .MEMORY_INIT_FILE       ("none"),
        .MEMORY_INIT_PARAM      ("0"),
        .MEMORY_OPTIMIZATION    ("true"),
        .MEMORY_PRIMITIVE       ("block"),
        .MEMORY_SIZE            (4096),     // 128 entries x 32 bits
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

    // ---- CPU-side: pkt_w / pkt_s / pkt_st acceptance ----
    // The RS stalls pkt_w/pkt_s on fifo_full but lets pkt_st through, so
    // valid pkts here are always accepted: a pkt_st observes status
    // without touching the BRAM or staging_ptr; a pkt_w/pkt_s only lands
    // when the FIFO isn't full (guaranteed by the RS-stall path).
    logic issue_pkt;
    logic issue_send;
    logic issue_write;
    logic issue_status;
    assign issue_status = pkt.valid &&  pkt.is_status;
    assign issue_send   = pkt.valid &&  pkt.is_send && !fifo_full;
    assign issue_write  = pkt.valid && !pkt.is_send && !pkt.is_status && !fifo_full;
    assign issue_pkt    = issue_status || issue_send || issue_write;

    // BRAM Port A write — only for pkt_w; addr selects staging slot.
    assign port_a_we   = issue_write;
    assign port_a_addr = {staging_ptr[BUF_DEPTH_BITS-1:0], pkt.word_offset};
    assign port_a_data = pkt.data;

    // Record per-slot length on pkt_s and advance staging_ptr.
    always_ff @(posedge clk) begin
        if (rst) begin
            staging_ptr <= '0;
            for (integer unsigned i = 0; i < BUF_DEPTH; i++)
                pkt_length[i] <= '0;
        end else if (issue_send) begin
            pkt_length[staging_ptr[BUF_DEPTH_BITS-1:0]] <= pkt.data[6:0];
            staging_ptr <= staging_ptr + 1'b1;
        end
    end

    // ---- HW drain FSM (declared early so the status mux can sample state) ----
    typedef enum logic [0:0] { TX_IDLE = 1'b0, TX_SEND = 1'b1 } tx_state_t;

    tx_state_t  state, state_n;
    logic [3:0] issue_idx, issue_idx_n;       // next BRAM word index to read
    logic [3:0] emit_idx,  emit_idx_n;        // index of the beat driven this cycle
    logic [3:0] total_words, total_words_n;   // ceil(length_octets / 4)
    logic [1:0] last_byte_cnt, last_byte_cnt_n;

    // ---- pkt_st: status read mux ----
    // Returns the selected status field through the CDB lane. pkt_st has
    // no BRAM or FSM interaction; the FU treats it as a single-cycle
    // observation (same path as pkt_w/pkt_s CDB writeback, registered
    // through pkt_pipe + status_pipe).
    //   imm 0  tx_empty   — staging FIFO empty AND drain FSM idle
    //   imm 1  tx_full    — staging FIFO full (next pkt_s would stall)
    //   imm 2  tx_busy    — drain FSM in SEND
    //   imm 3  tx_pending — count of staged packets not yet drained
    //   imm 4-7 reserved  — return 0
    logic [31:0] status_result;
    logic [BUF_DEPTH_BITS:0] pending_count;
    assign pending_count = staging_ptr - send_ptr;  // wraps via MSB
    always_comb begin
        unique case (pkt.word_offset[2:0])
            3'd0:    status_result = {31'b0, fifo_empty && (state == TX_IDLE)};
            3'd1:    status_result = {31'b0, fifo_full};
            3'd2:    status_result = {31'b0, (state == TX_SEND)};
            3'd3:    status_result = {28'b0, pending_count};
            default: status_result = 32'd0;
        endcase
    end
    logic       emit_valid_q, emit_valid_n;

    // Length decoding for the slot being picked up at IDLE->SEND.
    logic [6:0] start_length;
    logic [3:0] start_total_words;
    logic [1:0] start_last_byte_cnt;
    assign start_length        = pkt_length[send_ptr[BUF_DEPTH_BITS-1:0]];
    assign start_total_words   = (start_length[1:0] == 2'd0) ? start_length[5:2]
                                                             : (start_length[5:2] + 4'd1);
    assign start_last_byte_cnt = start_length[1:0];

    // BRAM Port B read address — uses send_ptr's slot.
    always_comb begin
        if (state == TX_IDLE && !fifo_empty) read_addr_b = {send_ptr[BUF_DEPTH_BITS-1:0], 4'd0};
        else if (state == TX_SEND)           read_addr_b = {send_ptr[BUF_DEPTH_BITS-1:0], issue_idx};
        else                                 read_addr_b = '0;
    end

    // FSM next-state logic. send_ptr only advances when the FSM finishes a
    // drain, so its update is folded into the always_ff below.
    logic send_ptr_advance;
    always_comb begin
        state_n          = state;
        issue_idx_n      = issue_idx;
        emit_idx_n       = emit_idx;
        total_words_n    = total_words;
        last_byte_cnt_n  = last_byte_cnt;
        emit_valid_n     = 1'b0;
        send_ptr_advance = 1'b0;

        unique case (state)
            TX_IDLE: begin
                if (!fifo_empty) begin
                    total_words_n   = start_total_words;
                    last_byte_cnt_n = start_last_byte_cnt;
                    issue_idx_n     = 4'd1;
                    emit_idx_n      = 4'd0;
                    emit_valid_n    = 1'b1;
                    state_n         = TX_SEND;
                end
            end
            TX_SEND: begin
                if (!m_axis_tready) begin
                    emit_valid_n = emit_valid_q;
                end else if (emit_idx == total_words - 4'd1) begin
                    state_n          = TX_IDLE;
                    emit_valid_n     = 1'b0;
                    send_ptr_advance = 1'b1;
                end else begin
                    emit_valid_n = 1'b1;
                    issue_idx_n  = issue_idx + 4'd1;
                    emit_idx_n   = emit_idx  + 4'd1;
                end
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state         <= TX_IDLE;
            send_ptr      <= '0;
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
            if (send_ptr_advance) send_ptr <= send_ptr + 1'b1;
        end
    end

    // ---- AXI-Stream output ----
    logic       is_last_beat;
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

    // The RS only needs to stall when the staging FIFO can't accept another
    // packet. The drain FSM running is fine — it's on a different slot.
    assign pkt_tx_busy = fifo_full;

    // ---- CDB writeback (1-cycle delayed from issue) ----
    // pkt_pipe holds the FU input for one cycle so cdb_pkt_tx can drive
    // from a registered packet. status_pipe carries the pkt_st result
    // alongside; for pkt_w/pkt_s it stays 0.
    fu_pkt_tx_pkt pkt_pipe;
    logic [31:0]  status_pipe;
    always_ff @(posedge clk) begin
        if (rst) begin
            pkt_pipe    <= '0;
            status_pipe <= 32'd0;
        end else begin
            pkt_pipe    <= '0;
            status_pipe <= 32'd0;
            if (issue_pkt) begin
                pkt_pipe <= pkt;
                if (pkt.is_status) status_pipe <= status_result;
            end
        end
    end

    always_comb begin
        cdb_pkt_tx = '{default: '0};
        if (pkt_pipe.valid) begin
            cdb_pkt_tx.valid     = 1'b1;
            // pkt_st returns the captured status value to rd; pkt_w/pkt_s
            // emit 0 (their rd is x0 in the firmware macros).
            cdb_pkt_tx.result    = pkt_pipe.is_status ? status_pipe : 32'd0;
            cdb_pkt_tx.rob_index = pkt_pipe.rob_index;
            cdb_pkt_tx.rd_paddr  = pkt_pipe.rd_paddr;
            cdb_pkt_tx.rd_addr   = pkt_pipe.rd_addr;
            // RVFI shadow expects rs1_rdata = actual rs1 value the CPU
            // read. pkt_st uses x0 (rs1_rdata = 0); pkt_w/pkt_s use the
            // architected rs1 carried in pkt.data.
            cdb_pkt_tx.rs1_val   = pkt_pipe.is_status ? 32'd0 : pkt_pipe.data;
            cdb_pkt_tx.rs2_val   = 32'd0;
        end
    end

endmodule : pkt_tx
