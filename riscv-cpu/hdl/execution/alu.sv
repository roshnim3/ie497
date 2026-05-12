module alu
import ooo_types::*;
(
    input  logic [31:0] rs1_val,
    input  logic [31:0] rs2_val,
    input  fu_alu_pkt   alu_pkt,

    output cdb_alu_pkt  cdb_alu
);

    always_comb begin
        if(alu_pkt.valid) begin
            // Handle comparison operations
            if(alu_pkt.cmp_op == cmp_lt)
                cdb_alu.result = {31'b0, ($signed(alu_pkt.op_a) < $signed(alu_pkt.op_b))};
            else if(alu_pkt.cmp_op == cmp_ltu)
                cdb_alu.result = {31'b0, (alu_pkt.op_a < alu_pkt.op_b)};
            else begin
                // Handle ALU operations
                unique case (alu_pkt.alu_op)
                    alu_add: cdb_alu.result = alu_pkt.op_a + alu_pkt.op_b;
                    alu_sll: cdb_alu.result = alu_pkt.op_a << alu_pkt.op_b[4:0];
                    alu_sra: cdb_alu.result = $unsigned($signed(alu_pkt.op_a) >>> alu_pkt.op_b[4:0]);
                    alu_sub: cdb_alu.result = alu_pkt.op_a - alu_pkt.op_b;
                    alu_xor: cdb_alu.result = alu_pkt.op_a ^ alu_pkt.op_b;
                    alu_srl: cdb_alu.result = alu_pkt.op_a >> alu_pkt.op_b[4:0];
                    alu_or:  cdb_alu.result = alu_pkt.op_a | alu_pkt.op_b;
                    alu_and: cdb_alu.result = alu_pkt.op_a & alu_pkt.op_b;
                    default: cdb_alu.result = 32'd0;
                endcase
            end
            
            // Set CDB packet fields
            cdb_alu.valid     = 1'b1;
            cdb_alu.rob_index = alu_pkt.rob_index;
            cdb_alu.rd_paddr  = alu_pkt.rd_paddr;
            cdb_alu.rd_addr   = alu_pkt.rd_addr;
            cdb_alu.rs1_val   = rs1_val;
            cdb_alu.rs2_val   = rs2_val;
        end else begin
            cdb_alu = '{default: '0};
        end
    end

endmodule : alu