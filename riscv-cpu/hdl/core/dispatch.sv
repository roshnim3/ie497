module dispatch 
import ooo_types::*;
(
    input  logic            flush,
    input  logic            rob_full,
    input  rename_packet_t  rename_pkt, 

    input  cdb_wakeup_pkt   cdb_alu_br_wakeup,
    input  cdb_wakeup_pkt   cdb_mul_div_wakeup,
    input  cdb_wakeup_pkt   cdb_mem_wakeup,

    // RS full signals
    input  logic            rs_br_full,
    input  logic            rs_alu_full,
    input  logic            rs_mul_full,
    input  logic            rs_div_full,
    input  logic            rs_mem_full,
    
    // LSQ index for mem operations
    input  logic [$clog2(LSQ_SIZE)-1:0] next_lsq_index,

    output logic            rs_full,

    // RS enqueue signals
    output rs_br_entry_t    rs_br_enq,
    output rs_alu_entry_t   rs_alu_enq,
    output rs_mul_entry_t   rs_mul_enq,
    output rs_div_entry_t   rs_div_enq,
    output rs_mem_entry_t   rs_mem_enq
);

    // Helper signals for CDB bypass detection
    logic rs1_cdb_match, rs2_cdb_match;

    assign rs1_cdb_match =  ((cdb_alu_br_wakeup.valid && (cdb_alu_br_wakeup.rd_paddr == rename_pkt.rs1_paddr))) ||
                            ((cdb_mul_div_wakeup.valid && (cdb_mul_div_wakeup.rd_paddr == rename_pkt.rs1_paddr))) ||
                            ((cdb_mem_wakeup.valid && (cdb_mem_wakeup.rd_paddr == rename_pkt.rs1_paddr)));
    assign rs2_cdb_match =  ((cdb_alu_br_wakeup.valid && (cdb_alu_br_wakeup.rd_paddr == rename_pkt.rs2_paddr))) ||
                            ((cdb_mul_div_wakeup.valid && (cdb_mul_div_wakeup.rd_paddr == rename_pkt.rs2_paddr))) ||
                            ((cdb_mem_wakeup.valid && (cdb_mem_wakeup.rd_paddr == rename_pkt.rs2_paddr)));

    always_comb begin
        // Default values to prevent latches
        rs_br_enq = '0;
        rs_alu_enq = '0;
        rs_mul_enq = '0;
        rs_div_enq = '0;
        rs_mem_enq = '0;
        
        // Don't dispatch if flush is active (pipeline is being flushed)
        if(rename_pkt.valid && !flush && !rob_full) begin        
            unique case (rename_pkt.fu_flag)
                FU_ALU: begin
                    rs_alu_enq.valid       = 1'b1;
                    rs_alu_enq.rs1_paddr   = rename_pkt.rs1_paddr;
                    rs_alu_enq.rs2_paddr   = rename_pkt.rs2_paddr;
                    rs_alu_enq.rd_paddr    = rename_pkt.rd_paddr;
                    rs_alu_enq.rd_addr     = rename_pkt.rd_addr;
                    rs_alu_enq.rs1_ready   = rename_pkt.rs1_ready || rs1_cdb_match;
                    rs_alu_enq.rs2_ready   = rename_pkt.rs2_ready || rs2_cdb_match;
                    rs_alu_enq.alu_op1_sel = rename_pkt.alu_op1_sel;
                    rs_alu_enq.alu_op2_sel = rename_pkt.alu_op2_sel;
                    rs_alu_enq.pc          = rename_pkt.pc;
                    rs_alu_enq.imm         = rename_pkt.imm;
                    rs_alu_enq.alu_op      = rename_pkt.alu_op;
                    rs_alu_enq.cmp_op      = rename_pkt.cmp_op;
                    rs_alu_enq.rob_index   = rename_pkt.rob_index;
                end
                FU_MUL: begin
                    rs_mul_enq.valid       = 1'b1;
                    rs_mul_enq.rs1_paddr   = rename_pkt.rs1_paddr;
                    rs_mul_enq.rs2_paddr   = rename_pkt.rs2_paddr;
                    rs_mul_enq.rd_paddr    = rename_pkt.rd_paddr;
                    rs_mul_enq.rd_addr     = rename_pkt.rd_addr;
                    rs_mul_enq.rs1_ready   = rename_pkt.rs1_ready || rs1_cdb_match;
                    rs_mul_enq.rs2_ready   = rename_pkt.rs2_ready || rs2_cdb_match;
                    rs_mul_enq.mul_op      = rename_pkt.mul_op;
                    rs_mul_enq.rob_index   = rename_pkt.rob_index;
                end
                FU_DIV: begin
                    rs_div_enq.valid       = 1'b1;
                    rs_div_enq.rs1_paddr   = rename_pkt.rs1_paddr;
                    rs_div_enq.rs2_paddr   = rename_pkt.rs2_paddr;
                    rs_div_enq.rd_paddr    = rename_pkt.rd_paddr;
                    rs_div_enq.rd_addr     = rename_pkt.rd_addr;
                    rs_div_enq.rs1_ready   = rename_pkt.rs1_ready || rs1_cdb_match;
                    rs_div_enq.rs2_ready   = rename_pkt.rs2_ready || rs2_cdb_match;
                    rs_div_enq.div_op      = rename_pkt.div_op;
                    rs_div_enq.rob_index   = rename_pkt.rob_index;
                end
                FU_BR: begin
                    rs_br_enq.valid       = rename_pkt.valid;
                    rs_br_enq.rs1_paddr   = rename_pkt.rs1_paddr;
                    rs_br_enq.rs2_paddr   = rename_pkt.rs2_paddr;
                    rs_br_enq.rd_paddr    = rename_pkt.rd_paddr;
                    rs_br_enq.rd_addr     = rename_pkt.rd_addr;
                    rs_br_enq.rs1_ready   = rename_pkt.rs1_ready || rs1_cdb_match;
                    rs_br_enq.rs2_ready   = rename_pkt.rs2_ready || rs2_cdb_match;
                    rs_br_enq.cmp_op      = rename_pkt.cmp_op;
                    rs_br_enq.pc          = rename_pkt.pc;
                    rs_br_enq.imm         = rename_pkt.imm;
                    rs_br_enq.pht_counter = rename_pkt.pht_counter;
                    rs_br_enq.pht_index   = rename_pkt.pht_index;
                    rs_br_enq.rob_index   = rename_pkt.rob_index;
                end
                FU_MEM: begin
                    rs_mem_enq.valid       = rename_pkt.valid && !rs_mem_full;
                    rs_mem_enq.rs1_paddr   = rename_pkt.rs1_paddr;
                    rs_mem_enq.rs2_paddr   = rename_pkt.rs2_paddr;
                    rs_mem_enq.rd_paddr    = rename_pkt.rd_paddr;
                    rs_mem_enq.rd_addr     = rename_pkt.rd_addr;
                    rs_mem_enq.rs1_ready   = rename_pkt.rs1_ready || rs1_cdb_match;
                    rs_mem_enq.rs2_ready   = rename_pkt.rs2_ready || rs2_cdb_match;
                    rs_mem_enq.mem_op      = rename_pkt.mem_op_type;
                    rs_mem_enq.mem_type    = rename_pkt.mem_type;
                    rs_mem_enq.pc          = rename_pkt.pc;
                    rs_mem_enq.imm         = rename_pkt.imm;
                    rs_mem_enq.rob_index   = rename_pkt.rob_index;
                    rs_mem_enq.lsq_index   = next_lsq_index;  // Physical LSQ index for direct update
                end
                default: begin
                    // Default case already handled by initial assignments
                end
            endcase
        end
    end

    always_comb begin
        unique case (rename_pkt.fu_flag)
            FU_BR:   rs_full = rs_br_full;
            FU_ALU:  rs_full = rs_alu_full;
            FU_MUL:  rs_full = rs_mul_full;
            FU_DIV:  rs_full = rs_div_full;
            FU_MEM:  rs_full = rs_mem_full;
            default:
                rs_full = 1'b0;
        endcase
    end


endmodule : dispatch