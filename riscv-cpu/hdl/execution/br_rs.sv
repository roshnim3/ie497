module br_rs 
import ooo_types::*;
#
(
    parameter RS_SIZE = 8
)
(
    input  logic            clk,
    input  logic            rst,
    input  logic            flush,
    input  rs_br_entry_t    new_entry,
    input  cdb_wakeup_pkt   cdb_alu_br_wakeup,
    input  cdb_wakeup_pkt   cdb_mul_div_wakeup,
    input  cdb_wakeup_pkt   cdb_mem_wakeup,

    output logic            rs_full,
    output logic            rs_empty,
    output rs_br_entry_t    rs_ready_entry
);
    // parallel access memory for BR RS
    rs_br_entry_t br_rs_mem [RS_SIZE];
    logic [$clog2(RS_SIZE):0] head, tail;
    logic [$clog2(RS_SIZE):0] ready_idx;

    assign rs_empty = (head == tail);
    assign rs_full  = (head[$clog2(RS_SIZE)] != tail[$clog2(RS_SIZE)]) && (head[$clog2(RS_SIZE)-1:0] == tail[$clog2(RS_SIZE)-1:0]);

    // Find first ready instruction from head to tail
    // always_comb begin
    //     rs_ready_entry = br_rs_mem[head[$clog2(RS_SIZE)-1:0]];
    //     ready_idx = head;
    //     if (!rs_empty) begin
    //         for (integer unsigned i = 0; i < RS_SIZE; i++) begin
    //             ready_idx = head + ($clog2(RS_SIZE)+1)'(i);

    //             if (ready_idx != tail) begin
    //                 if (br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].valid && 
    //                     br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].rs1_ready &&
    //                     br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].rs2_ready) begin
    //                     rs_ready_entry = br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]];
    //                     break;  
    //                 end
    //             end
    //         end
    //     end
    // end

    // assign rs_ready_entry = rs_empty ? '0 : br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]];

    // // Find first ready instruction from head to tail
    // always_ff @(posedge clk) begin
    //     ready_idx <= head;
    //     if (!rs_empty) begin
    //         for (integer unsigned i = 0; i < RS_SIZE; i++) begin
    //             if ((head + ($clog2(RS_SIZE)+1)'(i)) != tail) begin
    //                 if (br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].valid && 
    //                     br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].rs1_ready && 
    //                     br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].rs2_ready) begin
    //                         ready_idx <= head + ($clog2(RS_SIZE)+1)'(i);
    //                     break;  
    //                 end
    //             end
    //         end
    //     end
    // end

    // Find first ready instruction from head to tail
    always_comb begin
        ready_idx = head;
        if (!rs_empty) begin
            for (integer unsigned i = 0; i < RS_SIZE; i++) begin
                ready_idx = head + ($clog2(RS_SIZE)+1)'(i);
                if (ready_idx != tail) begin
                    if (br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].valid && 
                        br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].rs1_ready &&
                        br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].rs2_ready) begin
                            ready_idx = head + ($clog2(RS_SIZE)+1)'(i);
                            break;  
                    end
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if(rst) begin
            rs_ready_entry <= '0;
        end
        else begin
            rs_ready_entry <= (rs_empty | flush) ? '0 : br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            head <= '0;
            tail <= '0;
            for (integer unsigned i = 0; i < RS_SIZE; i++) begin
                br_rs_mem[i].valid <= '0;
            end
        end else if (flush) begin
            // On flush, invalidate all entries and reset to not ready
            head <= '0;
            tail <= '0;
            for (integer unsigned i = 0; i < RS_SIZE; i++) begin
                br_rs_mem[i].valid <= '0;
            end
        end else begin
            // Enqueue new entry - direct assignment
            if (new_entry.valid && !rs_full) begin
                br_rs_mem[tail[$clog2(RS_SIZE)-1:0]] <= new_entry;
                tail <= tail + 1'b1;
            end

            // Dequeue head entry if it's ready and been processed
            if (!rs_empty && 
                br_rs_mem[head[$clog2(RS_SIZE)-1:0]].rs1_ready && 
                br_rs_mem[head[$clog2(RS_SIZE)-1:0]].rs2_ready && 
                !br_rs_mem[head[$clog2(RS_SIZE)-1:0]].valid) begin
                
                br_rs_mem[head[$clog2(RS_SIZE)-1:0]].rs1_ready <= 1'b0;
                br_rs_mem[head[$clog2(RS_SIZE)-1:0]].rs2_ready <= 1'b0;
                head <= head + 1'b1;
            end

            // Set the entry at ready_idx to invalid after processing
            // Don't invalidate if we just enqueued at this position
            if (ready_idx != tail &&
                br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].rs1_ready &&
                br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].rs2_ready && 
                br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].valid) begin
                br_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].valid <= 1'b0;
            end

            // CDB broadcast - combine into single loop
            for (integer unsigned i = 0; i < RS_SIZE; i++) begin
                if (br_rs_mem[i].valid) begin
                    // Check rs1 ready
                    if (!br_rs_mem[i].rs1_ready && 
                        ((cdb_alu_br_wakeup.valid && (br_rs_mem[i].rs1_paddr == cdb_alu_br_wakeup.rd_paddr)) ||
                         (cdb_mul_div_wakeup.valid && (br_rs_mem[i].rs1_paddr == cdb_mul_div_wakeup.rd_paddr)) ||
                         (cdb_mem_wakeup.valid && (br_rs_mem[i].rs1_paddr == cdb_mem_wakeup.rd_paddr)))) begin
                        br_rs_mem[i].rs1_ready <= 1'b1;
                    end
                    
                    // Check rs2 ready
                    if (!br_rs_mem[i].rs2_ready && 
                        ((cdb_alu_br_wakeup.valid && (br_rs_mem[i].rs2_paddr == cdb_alu_br_wakeup.rd_paddr)) ||
                         (cdb_mul_div_wakeup.valid && (br_rs_mem[i].rs2_paddr == cdb_mul_div_wakeup.rd_paddr)) ||
                         (cdb_mem_wakeup.valid && (br_rs_mem[i].rs2_paddr == cdb_mem_wakeup.rd_paddr)))) begin
                        br_rs_mem[i].rs2_ready <= 1'b1;
                    end
                end
            end
        end
    end

endmodule : br_rs