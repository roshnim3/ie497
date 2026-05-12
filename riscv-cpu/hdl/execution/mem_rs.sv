module mem_rs 
import ooo_types::*;
#
(
    parameter RS_SIZE = 8
)
(
    input  logic            clk,
    input  logic            rst,
    input  logic            flush,
    input  rs_mem_entry_t   new_entry,
    input  cdb_wakeup_pkt   cdb_alu_br_wakeup,
    input  cdb_wakeup_pkt   cdb_mul_div_wakeup,
    input  cdb_wakeup_pkt   cdb_mem_wakeup,

    output logic            rs_full,
    output logic            rs_empty,
    output rs_mem_entry_t   rs_ready_entry
);
    // parallel access memory for MEM RS
    rs_mem_entry_t mem_rs_mem [RS_SIZE];
    logic [$clog2(RS_SIZE):0] head, tail;
    logic [$clog2(RS_SIZE):0] ready_idx;

    assign rs_empty = (head == tail);
    assign rs_full  = (head[$clog2(RS_SIZE)] != tail[$clog2(RS_SIZE)]) && (head[$clog2(RS_SIZE)-1:0] == tail[$clog2(RS_SIZE)-1:0]);

    // Find first ready instruction from head to tail
    // always_comb begin
    //     rs_ready_entry = mem_rs_mem[head[$clog2(RS_SIZE)-1:0]];
    //     ready_idx = head;
    //     if (!rs_empty) begin
    //         for (integer unsigned i = 0; i < RS_SIZE; i++) begin
    //             ready_idx = head + ($clog2(RS_SIZE)+1)'(i);

    //             if (ready_idx != tail) begin
    //                 if (mem_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].valid && 
    //                     mem_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].rs1_ready &&
    //                     mem_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].rs2_ready) begin
    //                     rs_ready_entry = mem_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]];
    //                     break;  
    //                 end
    //             end
    //         end
    //     end
    // end

    // assign rs_ready_entry = (rs_empty | flush) ? '0 : mem_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]];

    // Find first ready instruction from head to tail - combinational
    // always_comb begin
    //     ready_idx = head;
    //     if (!rs_empty && !flush) begin
    //         for (integer unsigned i = 0; i < RS_SIZE; i++) begin
    //             logic [$clog2(RS_SIZE):0] curr_idx;
    //             curr_idx = head + ($clog2(RS_SIZE)+1)'(i);
    //             if (curr_idx != tail) begin
    //                 if (mem_rs_mem[curr_idx[$clog2(RS_SIZE)-1:0]].valid && 
    //                     mem_rs_mem[curr_idx[$clog2(RS_SIZE)-1:0]].rs1_ready && 
    //                     mem_rs_mem[curr_idx[$clog2(RS_SIZE)-1:0]].rs2_ready) begin
    //                         ready_idx = curr_idx;
    //                     break;  
    //                 end
    //             end
    //         end
    //     end
    // end

    // always_ff @(posedge clk) begin
    //     ready_idx <= head;
    //     if (!rs_empty) begin
    //         for (integer unsigned i = 0; i < RS_SIZE; i++) begin
    //             if ((head + ($clog2(RS_SIZE)+1)'(i)) != tail) begin
    //                 if (mem_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].valid && 
    //                     mem_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].rs1_ready && 
    //                     mem_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].rs2_ready) begin
    //                         ready_idx <= head + ($clog2(RS_SIZE)+1)'(i);
    //                     break;  
    //                 end
    //             end
    //         end
    //     end
    // end

    always_comb begin
        ready_idx = head;
        if (!rs_empty) begin
            for (integer unsigned i = 0; i < RS_SIZE; i++) begin
                ready_idx = head + ($clog2(RS_SIZE))'(i);
                if (ready_idx != tail) begin
                    if (mem_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].valid && 
                        mem_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].rs1_ready &&
                        mem_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]].rs2_ready) begin
                            ready_idx = head + ($clog2(RS_SIZE))'(i);
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
            rs_ready_entry <= (rs_empty | flush) ? '0 : mem_rs_mem[ready_idx[$clog2(RS_SIZE)-1:0]];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            head <= '0;
            tail <= '0;
            for (integer unsigned i = 0; i < RS_SIZE; i++) begin
                mem_rs_mem[i].valid <= '0;
            end
        end else if (flush) begin
            head <= '0;
            tail <= '0;

            for (integer unsigned i = 0; i < RS_SIZE; i++) begin
                mem_rs_mem[i].valid <= '0;
            end
        end else begin
            // Enqueue new entry - trust new_entry.valid (already gated by rename checking rs_mem_or_lsq_full)
            if (new_entry.valid) begin
                mem_rs_mem[tail[$clog2(RS_SIZE)-1:0]] <= new_entry;
                tail <= tail + 1'b1;
            end

            // Invalidate entry when addr/data is calculated (ready_entry with both operands ready)
            // This frees up RS slot immediately after calculation, LSQ uses ROB idx for updates
            if (rs_ready_entry.valid && rs_ready_entry.rs1_ready && rs_ready_entry.rs2_ready) begin
                for (integer unsigned i = 0; i < RS_SIZE; i++) begin
                    if (mem_rs_mem[i].valid && 
                        mem_rs_mem[i].rob_index == rs_ready_entry.rob_index) begin
                        mem_rs_mem[i].valid <= 1'b0;
                        break;
                    end
                end
            end

            // Move head forward when head entry is invalid
            if (!rs_empty && !mem_rs_mem[head[$clog2(RS_SIZE)-1:0]].valid) begin
                head <= head + 1'b1;
            end

            // CDB broadcast - combine into single loop
            for (integer unsigned i = 0; i < RS_SIZE; i++) begin
                if (mem_rs_mem[i].valid) begin
                    // Check rs1 ready
                    if (!mem_rs_mem[i].rs1_ready && 
                        ((cdb_alu_br_wakeup.valid && (mem_rs_mem[i].rs1_paddr == cdb_alu_br_wakeup.rd_paddr)) ||
                         (cdb_mul_div_wakeup.valid && (mem_rs_mem[i].rs1_paddr == cdb_mul_div_wakeup.rd_paddr)) ||
                         (cdb_mem_wakeup.valid && (mem_rs_mem[i].rs1_paddr == cdb_mem_wakeup.rd_paddr)))) begin
                        mem_rs_mem[i].rs1_ready <= 1'b1;
                    end
                    
                    // Check rs2 ready
                    if (!mem_rs_mem[i].rs2_ready && 
                        ((cdb_alu_br_wakeup.valid && (mem_rs_mem[i].rs2_paddr == cdb_alu_br_wakeup.rd_paddr)) ||
                         (cdb_mul_div_wakeup.valid && (mem_rs_mem[i].rs2_paddr == cdb_mul_div_wakeup.rd_paddr)) ||
                         (cdb_mem_wakeup.valid && (mem_rs_mem[i].rs2_paddr == cdb_mem_wakeup.rd_paddr)))) begin
                        mem_rs_mem[i].rs2_ready <= 1'b1;
                    end
                end
            end
        end
    end

endmodule : mem_rs