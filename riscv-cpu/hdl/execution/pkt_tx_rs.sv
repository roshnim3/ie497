// pkt_tx reservation station.
//
// custom-2 has one source operand (rs1):
//   pkt_w  — rs1 holds the payload word (32b) to write to the TX BRAM.
//   pkt_s  — rs1 holds the length (in octets) to emit on AXI-Stream.
// Watches the three CDB lanes for rs1 wakeup. No rs2.
//
// The stall input parks the head while the FU can't accept a new entry.
// In Phase 2 the FU only stalls when its staging FIFO is full (8 packets
// queued); ordinary back-to-back pkt_w/pkt_s issue freely.

module pkt_tx_rs
import ooo_types::*;
#(
    parameter RS_SIZE = 4
)
(
    input  logic                clk,
    input  logic                rst,
    input  logic                flush,
    input  logic                stall,
    input  rs_pkt_tx_entry_t    new_entry,
    input  cdb_wakeup_pkt       cdb_alu_br_wakeup,
    input  cdb_wakeup_pkt       cdb_mul_div_wakeup,
    input  cdb_wakeup_pkt       cdb_mem_wakeup,

    output logic                rs_full,
    output logic                rs_empty,
    output rs_pkt_tx_entry_t    rs_ready_entry
);
    rs_pkt_tx_entry_t pt_rs_mem [RS_SIZE];
    logic [$clog2(RS_SIZE):0] head, tail;

    assign rs_empty = (head == tail);
    assign rs_full  = (head[$clog2(RS_SIZE)] != tail[$clog2(RS_SIZE)]) &&
                      (head[$clog2(RS_SIZE)-1:0] == tail[$clog2(RS_SIZE)-1:0]);

    logic head_ready;
    logic head_is_status;
    assign head_ready = !rs_empty &&
                        pt_rs_mem[head[$clog2(RS_SIZE)-1:0]].valid &&
                        pt_rs_mem[head[$clog2(RS_SIZE)-1:0]].rs1_ready;
    // pkt_st is a pure observation read — let it bypass the staging-full
    // stall so firmware can keep polling tx_full / tx_empty even while the
    // FIFO is saturated. The FU treats pkt_st as a no-op against the
    // BRAM and FSM, just snapshots status onto the CDB.
    assign head_is_status = pt_rs_mem[head[$clog2(RS_SIZE)-1:0]].is_status;

    // Issue when the head is ready, and either the FU has staging room
    // (for pkt_w / pkt_s) or the head is a pkt_st.
    assign rs_ready_entry = (head_ready && (!stall || head_is_status)) ?
                            pt_rs_mem[head[$clog2(RS_SIZE)-1:0]] : '0;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            head <= '0;
            tail <= '0;
            for (integer unsigned i = 0; i < RS_SIZE; i++)
                pt_rs_mem[i].valid <= '0;
        end else begin
            if (new_entry.valid && !rs_full) begin
                pt_rs_mem[tail[$clog2(RS_SIZE)-1:0]] <= new_entry;
                tail <= tail + 1'b1;
            end

            if (head_ready && (!stall || head_is_status)) begin
                pt_rs_mem[head[$clog2(RS_SIZE)-1:0]].valid <= 1'b0;
                head <= head + 1'b1;
            end

            // rs1 wakeup from any CDB lane
            for (integer unsigned i = 0; i < RS_SIZE; i++) begin
                if (pt_rs_mem[i].valid && !pt_rs_mem[i].rs1_ready &&
                    ((cdb_alu_br_wakeup.valid  && (pt_rs_mem[i].rs1_paddr == cdb_alu_br_wakeup.rd_paddr))  ||
                     (cdb_mul_div_wakeup.valid && (pt_rs_mem[i].rs1_paddr == cdb_mul_div_wakeup.rd_paddr)) ||
                     (cdb_mem_wakeup.valid     && (pt_rs_mem[i].rs1_paddr == cdb_mem_wakeup.rd_paddr)))) begin
                    pt_rs_mem[i].rs1_ready <= 1'b1;
                end
            end
        end
    end

endmodule : pkt_tx_rs
