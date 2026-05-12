module rename 
import ooo_types::*;
(
    input logic             flush,
    input logic [5:0]       alloc_reg,
    input logic             freelist_empty,
    input logic             rs_full,
    input logic             rob_full,
    input decode_packet_t   decode_pkt,
    input rat_entry_t       rat_rs1_rdata,
    input rat_entry_t       rat_rs2_rdata,
    input rvfi_packet_t     decode_rvfi_pkt,
    input [$clog2(ROB_SIZE) - 1: 0] rob_index,

    output logic            alloc_req,
    output logic [4:0]      rat_rs1_raddr,
    output logic [4:0]      rat_rs2_raddr,
    output logic            rat_wen,
    output logic [4:0]      rat_waddr,
    output rat_entry_t      rat_wdata,

    output rename_packet_t  rename_pkt,
    output rob_entry_t      rob_entry
);
    logic rs1_cdb_match;
    logic rs2_cdb_match;

    // Output read addresses for RAT
    assign rat_rs1_raddr = decode_pkt.rs1_addr;
    assign rat_rs2_raddr = decode_pkt.rs2_addr;

    // We dont need the CDBs if this stage is just combinational
    //
    // assign rs1_cdb_match = (cdb_alu.valid && (cdb_alu.rd_paddr == rat[decode_pkt.rs1_addr].phys_reg)) ||
    //                        (cdb_mul.valid && (cdb_mul.rd_paddr == rat[decode_pkt.rs1_addr].phys_reg)) ||
    //                        (cdb_div.valid && (cdb_div.rd_paddr == rat[decode_pkt.rs1_addr].phys_reg));

    // assign rs2_cdb_match = (cdb_alu.valid && (cdb_alu.rd_paddr == rat[decode_pkt.rs2_addr].phys_reg)) ||
    //                        (cdb_mul.valid && (cdb_mul.rd_paddr == rat[decode_pkt.rs2_addr].phys_reg)) ||
    //                        (cdb_div.valid && (cdb_div.rd_paddr == rat[decode_pkt.rs2_addr].phys_reg));

    always_comb begin
        if(decode_pkt.valid && !freelist_empty && !rob_full && !flush) begin
            alloc_req  = (decode_pkt.rd_addr != 5'd0) && !rs_full;
            rat_wen    = alloc_req;
            rat_waddr  = decode_pkt.rd_addr;
            rat_wdata  = alloc_req ? '{phys_reg: alloc_reg, ready: 1'b0, valid: 1'b1} : '0;

            rename_pkt.valid       = 1'b1;
            rename_pkt.inst        = decode_pkt.inst;
            rename_pkt.pc          = decode_pkt.pc;
            rename_pkt.rs1_paddr   = rat_rs1_rdata.phys_reg;
            rename_pkt.rs2_paddr   = rat_rs2_rdata.phys_reg;
            rename_pkt.rs1_ready   = rat_rs1_rdata.ready;
            rename_pkt.rs2_ready   = rat_rs2_rdata.ready;
            rename_pkt.imm         = decode_pkt.imm;
            rename_pkt.rd_paddr    = alloc_req ? alloc_reg : 6'd0;
            rename_pkt.rd_addr     = decode_pkt.rd_addr;
            rename_pkt.fu_flag     = decode_pkt.fu_flag;
            rename_pkt.alu_op      = decode_pkt.alu_op;
            rename_pkt.alu_op1_sel = decode_pkt.alu_op1_sel;
            rename_pkt.alu_op2_sel = decode_pkt.alu_op2_sel;
            rename_pkt.cmp_op      = decode_pkt.cmp_op;
            rename_pkt.mul_op      = decode_pkt.mul_op;
            rename_pkt.div_op      = decode_pkt.div_op;
            rename_pkt.pht_counter = decode_pkt.pht_counter;
            rename_pkt.pht_index   = decode_pkt.pht_index;
            rename_pkt.mem_type    = decode_pkt.mem_type;
            rename_pkt.mem_op_type = decode_pkt.mem_op_type;
            rename_pkt.rob_index   = rob_index;


            rob_entry.valid         = !rs_full;
            rob_entry.state         = WAIT;
            rob_entry.pc            = decode_pkt.pc;
            rob_entry.inst          = decode_pkt.inst;
            rob_entry.order         = decode_rvfi_pkt.order;
            rob_entry.rd_addr       = decode_pkt.rd_addr;
            rob_entry.rd_paddr      = rename_pkt.rd_paddr; 
            rob_entry.br_pred       = decode_pkt.br_pred;
            rob_entry.br_result     = not_taken;
            rob_entry.pht_counter   = decode_pkt.pht_counter;
            rob_entry.pht_index     = decode_pkt.pht_index;
            rob_entry.branch_target = 32'd0;
            rob_entry.rvfi_pkt      = decode_rvfi_pkt;
            
        end else begin
            alloc_req  = 1'b0;
            rat_wen    = 1'b0;
            rat_waddr  = 5'd0;
            rat_wdata  = '0;

            rename_pkt = '0;
            rename_pkt.valid = 1'b0;

            rob_entry  = '0;
        end
    end

endmodule : rename