module rob
import ooo_types::*;
(
    input  logic                clk,
    input  logic                rst,
    input  rob_entry_t          new_entry,
    input  cdb_alu_br_rob_pkt   cdb_alu_br_rob,
    input  cdb_mul_div_rob_pkt  cdb_mul_div_rob,
    input  cdb_mem_pkt          cdb_mem,
    input  logic                bp_update_queue_full,  // Stall branch commits if BP queue full

    output logic            full,
    output logic            empty,
    output logic [1:0]      commit,
    output logic [1:0]      flush,
    output rob_entry_t [1:0]     head_entry,
    output [$clog2(ROB_SIZE) - 1 : 0] rob_index,
    output [$clog2(ROB_SIZE) - 1 : 0] head_index
);

    // parallel access memory for ROB
    rob_entry_t rob_mem [ROB_SIZE];
    logic [$clog2(ROB_SIZE) : 0] head, head_plus_1, tail;
    
    // Check if head instruction is a branch (needs BP update)
    logic head_is_branch, head_plus_1_is_branch;
    logic head_is_jalr, head_plus_1_is_jalr;
    logic head_target_mispred, head_plus_1_target_mispred;
    
    // Detect JALR instructions (opcode = 7'b1100111)
    assign head_is_jalr = (rob_mem[head[$clog2(ROB_SIZE)-1:0]].inst[6:0] == 7'b1100111);
    assign head_plus_1_is_jalr = (rob_mem[head_plus_1[$clog2(ROB_SIZE)-1:0]].inst[6:0] == 7'b1100111);
    
    // For JALR, we can't predict the target, so always assume misprediction
    // For taken branches, check if target matches (but we don't store predicted target...)
    // For now, JALR always causes flush since we don't have target prediction
    assign head_target_mispred = head_is_jalr;
    assign head_plus_1_target_mispred = head_plus_1_is_jalr;
    
    assign head_is_branch = (rob_mem[head[$clog2(ROB_SIZE)-1:0]].br_pred != rob_mem[head[$clog2(ROB_SIZE)-1:0]].br_result) ||
                            (rob_mem[head[$clog2(ROB_SIZE)-1:0]].br_result == taken);
    assign head_plus_1_is_branch = (rob_mem[head_plus_1[$clog2(ROB_SIZE)-1:0]].br_pred != rob_mem[head_plus_1[$clog2(ROB_SIZE)-1:0]].br_result) ||
                                    (rob_mem[head_plus_1[$clog2(ROB_SIZE)-1:0]].br_result == taken);

    assign head_plus_1 = head + 1'b1;

    assign empty = (head == tail);
    assign full  = (head[$clog2(ROB_SIZE)] != tail[$clog2(ROB_SIZE)]) && (head[$clog2(ROB_SIZE)-1:0] == tail[$clog2(ROB_SIZE)-1:0]);

    assign head_entry[0] = empty ? '0 : rob_mem[head[$clog2(ROB_SIZE)-1:0]];
    assign head_entry[1] = ((head_plus_1 != tail) && !empty) ? rob_mem[head_plus_1[$clog2(ROB_SIZE)-1:0]] : '0;

    // Don't commit branches if BP update queue is full
    assign commit[0] = !empty & (rob_mem[head[$clog2(ROB_SIZE)-1:0]].valid && rob_mem[head[$clog2(ROB_SIZE)-1:0]].state == READY) &&
                       !(head_is_branch && bp_update_queue_full);
    assign commit[1] = !flush[0] && (head_plus_1 != tail) && 
                       commit[0] && 
                       (rob_mem[head_plus_1[$clog2(ROB_SIZE)-1:0]].valid && rob_mem[head_plus_1[$clog2(ROB_SIZE)-1:0]].state == READY) &&
                       !(head_plus_1_is_branch && bp_update_queue_full);

    assign rob_index = tail[$clog2(ROB_SIZE) - 1:0];
    assign head_index = head[$clog2(ROB_SIZE) - 1:0];

    // Flush detection: branch misprediction OR target misprediction at ROB head when committing
    // Target misprediction occurs for JALR (we can't predict target without BTB/RAS)
    assign flush[0] = commit[0] && rob_mem[head[$clog2(ROB_SIZE)-1:0]].valid && 
                   ((rob_mem[head[$clog2(ROB_SIZE)-1:0]].br_pred != rob_mem[head[$clog2(ROB_SIZE)-1:0]].br_result) ||
                    head_target_mispred);
    assign flush[1] = commit[1] && !flush[0] && (head_plus_1 != tail) && rob_mem[head_plus_1[$clog2(ROB_SIZE)-1:0]].valid &&
                   ((rob_mem[head_plus_1[$clog2(ROB_SIZE)-1:0]].br_pred != rob_mem[head_plus_1[$clog2(ROB_SIZE)-1:0]].br_result) ||
                    head_plus_1_target_mispred);

    always_ff @(posedge clk) begin
        if (rst) begin
            head <= '0;
            tail <= '0;
            for (integer unsigned i = 0; i < ROB_SIZE; i++) begin
                rob_mem[i].valid <= 1'b0;
            end
        end else if (|flush) begin
            // Invalidate all ROB entries except the flushing instruction(s)
            // Then advance head and reset tail
            if(flush[0]) begin
                for (integer i = 0; i < ROB_SIZE; i++) begin
                    rob_mem[i].valid <= 1'b0;
                end
                rob_mem[head[$clog2(ROB_SIZE)-1:0]].valid <= 1'b1;  // Keep the flushing branch valid for commit
                head <= head + 1'b1;
                tail <= head + 1'b1;
            end else if(flush[1])  begin
                for (integer i = 0; i < ROB_SIZE; i++) begin
                    rob_mem[i].valid <= 1'b0;
                end
                rob_mem[head[$clog2(ROB_SIZE)-1:0]].valid <= 1'b1;
                rob_mem[head_plus_1[$clog2(ROB_SIZE)-1:0]].valid <= 1'b1;
                tail <= head + 2'b10;
                head <= head + 2'b10;        
            end
        end else begin
            // Enqueue new entry
            if (new_entry.valid && !full) begin
                rob_mem[tail[$clog2(ROB_SIZE)-1:0]] <= new_entry;
                tail <= tail + 1'b1;            end

            // Commit and dequeue head entry
            if (!empty && (rob_mem[head[$clog2(ROB_SIZE)-1:0]].state == READY)) begin
                rob_mem[head[$clog2(ROB_SIZE)-1:0]].valid <= 1'b0;
                head <= head + 1'b1;            
            end
            if (!empty && commit[1] && (head_plus_1 != tail) && (rob_mem[head_plus_1[$clog2(ROB_SIZE)-1:0]].state == READY)) begin
                rob_mem[head_plus_1[$clog2(ROB_SIZE)-1:0]].valid <= 1'b0;
                head <= head + 2'b10;            
            end

            // CDB broadcast - update ROB entries when instructions complete
            if (cdb_alu_br_rob.valid) begin
                rob_mem[cdb_alu_br_rob.rob_index].state               <= READY;
                rob_mem[cdb_alu_br_rob.rob_index].rvfi_pkt.rd_wdata  <= cdb_alu_br_rob.result;
                rob_mem[cdb_alu_br_rob.rob_index].rvfi_pkt.rs1_rdata <= cdb_alu_br_rob.rs1_val;
                rob_mem[cdb_alu_br_rob.rob_index].rvfi_pkt.rs2_rdata <= cdb_alu_br_rob.rs2_val;
                rob_mem[cdb_alu_br_rob.rob_index].rvfi_pkt.valid     <= 1'b1;
                // Update branch-specific fields (only meaningful for branch instructions)
                rob_mem[cdb_alu_br_rob.rob_index].br_result          <= cdb_alu_br_rob.br_result;
                rob_mem[cdb_alu_br_rob.rob_index].branch_target      <= cdb_alu_br_rob.branch_target;
                // Update pc_wdata to reflect actual next PC (branch_target if taken, else pc+4)
                // For non-branch instructions, br_result will be not_taken, so this defaults to pc+4
                rob_mem[cdb_alu_br_rob.rob_index].rvfi_pkt.pc_wdata  <= (cdb_alu_br_rob.br_result == taken) ? 
                                                                     cdb_alu_br_rob.branch_target : 
                                                                     (rob_mem[cdb_alu_br_rob.rob_index].pc + 32'd4);            
            end

            if (cdb_mul_div_rob.valid) begin
                rob_mem[cdb_mul_div_rob.rob_index].state               <= READY;
                rob_mem[cdb_mul_div_rob.rob_index].rvfi_pkt.rd_wdata  <= cdb_mul_div_rob.result;
                rob_mem[cdb_mul_div_rob.rob_index].rvfi_pkt.rs1_rdata <= cdb_mul_div_rob.rs1_val;
                rob_mem[cdb_mul_div_rob.rob_index].rvfi_pkt.rs2_rdata <= cdb_mul_div_rob.rs2_val;
                rob_mem[cdb_mul_div_rob.rob_index].rvfi_pkt.valid     <= 1'b1;            
            end

            if (cdb_mem.valid) begin
                rob_mem[cdb_mem.rob_index].state                 <= READY;
                rob_mem[cdb_mem.rob_index].rvfi_pkt.rd_wdata    <= cdb_mem.result;
                rob_mem[cdb_mem.rob_index].rvfi_pkt.rs1_rdata   <= cdb_mem.rs1_val;
                rob_mem[cdb_mem.rob_index].rvfi_pkt.rs2_rdata   <= cdb_mem.rs2_val;
                rob_mem[cdb_mem.rob_index].rvfi_pkt.mem_addr    <= cdb_mem.mem_addr;
                rob_mem[cdb_mem.rob_index].rvfi_pkt.mem_rmask   <= cdb_mem.mem_rmask;
                rob_mem[cdb_mem.rob_index].rvfi_pkt.mem_wmask   <= cdb_mem.mem_wmask;
                rob_mem[cdb_mem.rob_index].rvfi_pkt.mem_rdata   <= cdb_mem.mem_rdata;
                rob_mem[cdb_mem.rob_index].rvfi_pkt.mem_wdata   <= cdb_mem.mem_wdata;
                rob_mem[cdb_mem.rob_index].rvfi_pkt.valid       <= 1'b1;            
            end
        end
    end

endmodule