module rrat 
import ooo_types::*;
(
    input logic             clk,
    input logic             rst,
    input logic [1:0]       commit,
    input rob_commit_pkt [1:0]    rob_commit,

    output rat_entry_t rrat_out [31:0],
    output logic [1:0][5:0]       free_reg,
    output logic [1:0]            free_req

);

    rat_entry_t rrat_table [31:0];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (integer unsigned i = 0; i < 32; i++) begin
                rrat_table[i] <= '{phys_reg: 6'(i), ready: 1'b1, valid: 1'b1};
            end
        end else begin
            if (commit[0]) begin
                rrat_table[rob_commit[0].rd_addr] <= '{phys_reg: rob_commit[0].rd_paddr, ready: 1'b1, valid: 1'b1};
            end
            if (commit[1]) begin
                rrat_table[rob_commit[1].rd_addr] <= '{phys_reg: rob_commit[1].rd_paddr, ready: 1'b1, valid: 1'b1};
            end
        end
    end

    always_comb begin
        free_req = '0;
        free_reg = '0;
        if (commit[0] && rob_commit[0].valid && rob_commit[0].rd_addr != 0 &&
            rrat_table[rob_commit[0].rd_addr].phys_reg != rob_commit[0].rd_paddr) begin
            free_req[0] = 1'b1;
            free_reg[0] = rrat_table[rob_commit[0].rd_addr].phys_reg;
        end
        if (commit[1] && rob_commit[1].valid && rob_commit[1].rd_addr != 0 &&
            rrat_table[rob_commit[1].rd_addr].phys_reg != rob_commit[1].rd_paddr) begin
            free_req[1] = 1'b1;
            free_reg[1] = rrat_table[rob_commit[1].rd_addr].phys_reg;
        end
    end


    assign rrat_out = rrat_table;

endmodule : rrat