module br
import ooo_types::*;
(
    input  fu_br_pkt   br_pkt,

    output cdb_br_pkt  cdb_br
);

    logic branch_taken;
    logic [31:0] branch_target;
    logic [31:0] link_addr;
    
    always_comb begin
        cdb_br = '0;
        cdb_br.br_result = not_taken;
        
        if (br_pkt.valid) begin
            // Default: branches compute PC + imm, JAL/JALR override later
            branch_target = br_pkt.pc + br_pkt.imm;
            link_addr = br_pkt.pc + 4;
            
            // Branch decision logic
            unique case (br_pkt.cmp_op)
                cmp_eq:  branch_taken = (br_pkt.op_a == br_pkt.op_b);
                cmp_ne:  branch_taken = (br_pkt.op_a != br_pkt.op_b);
                cmp_lt:  branch_taken = ($signed(br_pkt.op_a) < $signed(br_pkt.op_b));
                cmp_ge:  branch_taken = ($signed(br_pkt.op_a) >= $signed(br_pkt.op_b));
                cmp_ltu: branch_taken = (br_pkt.op_a < br_pkt.op_b);
                cmp_geu: branch_taken = (br_pkt.op_a >= br_pkt.op_b);
                jal: begin
                    branch_taken = 1'b1;
                    branch_target = br_pkt.pc + br_pkt.imm;
                end
                jalr: begin
                    branch_taken = 1'b1;
                    branch_target = br_pkt.op_a + br_pkt.imm;
                end
                default: branch_taken = 1'b0;
            endcase

            // Set CDB packet fields
            cdb_br.valid         = 1'b1;
            cdb_br.result        = (br_pkt.cmp_op == jal || br_pkt.cmp_op == jalr) ? link_addr : '0;
            cdb_br.rob_index     = br_pkt.rob_index;
            cdb_br.rd_paddr      = br_pkt.rd_paddr;
            cdb_br.rd_addr       = br_pkt.rd_addr;
            cdb_br.rs1_val       = br_pkt.op_a;
            cdb_br.rs2_val       = br_pkt.op_b;
            cdb_br.branch_target = branch_target;
            cdb_br.br_result     = branch_taken ? taken : not_taken;
            cdb_br.pht_counter   = br_pkt.pht_counter;
            cdb_br.pht_index     = br_pkt.pht_index;
            cdb_br.is_conditional = (br_pkt.cmp_op != jal && br_pkt.cmp_op != jalr);
        end
    end

endmodule : br