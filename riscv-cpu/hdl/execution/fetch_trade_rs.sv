// fetch_trade reservation station — minimal FIFO.
//
// custom-1 has no source operands (rs1=x0, no rs2), so the usual wakeup
// machinery isn't needed; entries are issuable the moment they're enqueued.
// Each cycle, if non-empty, the head entry is presented to the FU and the
// FIFO advances. The FU back-pressure mechanism for CDB contention lives in
// cpu.sv via trade_result_buffer.

module fetch_trade_rs
import ooo_types::*;
#(
    parameter RS_SIZE = 4
)
(
    input  logic                   clk,
    input  logic                   rst,
    input  logic                   flush,
    input  rs_fetch_trade_entry_t  new_entry,

    output logic                   rs_full,
    output logic                   rs_empty,
    output rs_fetch_trade_entry_t  rs_ready_entry
);
    rs_fetch_trade_entry_t ft_rs_mem [RS_SIZE];
    logic [$clog2(RS_SIZE):0] head, tail;

    assign rs_empty = (head == tail);
    assign rs_full  = (head[$clog2(RS_SIZE)] != tail[$clog2(RS_SIZE)]) &&
                      (head[$clog2(RS_SIZE)-1:0] == tail[$clog2(RS_SIZE)-1:0]);

    assign rs_ready_entry = rs_empty ? '0 : ft_rs_mem[head[$clog2(RS_SIZE)-1:0]];

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            head <= '0;
            tail <= '0;
            for (integer unsigned i = 0; i < RS_SIZE; i++)
                ft_rs_mem[i].valid <= '0;
        end else begin
            // Enqueue from dispatch
            if (new_entry.valid && !rs_full) begin
                ft_rs_mem[tail[$clog2(RS_SIZE)-1:0]] <= new_entry;
                tail <= tail + 1'b1;
            end

            // Issue + dequeue head every cycle when non-empty
            if (!rs_empty) begin
                ft_rs_mem[head[$clog2(RS_SIZE)-1:0]].valid <= 1'b0;
                head <= head + 1'b1;
            end
        end
    end

endmodule : fetch_trade_rs
