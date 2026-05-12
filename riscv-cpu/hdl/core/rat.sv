module rat 
import ooo_types::*;
(
    input logic            clk,
    input logic            rst,
    input logic            flush,
    input logic [1:0]      commit,
    input rob_commit_pkt [1:0]    rob_commit,
    input rat_entry_t      rrat_out [31:0],
    input logic [4:0]      rat_rs1_raddr,
    input logic [4:0]      rat_rs2_raddr,
    input logic            rat_wen,
    input logic [4:0]      rat_waddr,
    input rat_entry_t      rat_wdata,
    input cdb_rat_pkt      cdb_alu_br_rat,
    input cdb_rat_pkt      cdb_mul_div_rat,
    input cdb_rat_pkt      cdb_mem_rat,

    output rat_entry_t     rat_rs1_rdata,
    output rat_entry_t     rat_rs2_rdata,
    output rat_entry_t     rat_out [31:0]
);

    rat_entry_t rat_table [31:0];
    rat_entry_t rrat_for_flush [31:0];

    // Compute the RRAT state to use for flush, accounting for simultaneous commit
    always_comb begin
        rrat_for_flush = rrat_out;
        // If we're committing and flushing simultaneously, use the updated RRAT mapping
        if (commit[0] && (rob_commit[0].rd_addr != 5'd0)) begin
            rrat_for_flush[rob_commit[0].rd_addr] = '{phys_reg: rob_commit[0].rd_paddr, ready: 1'b1, valid: 1'b1};
        end
        if (commit[1] && (rob_commit[1].rd_addr != 5'd0)) begin
            rrat_for_flush[rob_commit[1].rd_addr] = '{phys_reg: rob_commit[1].rd_paddr, ready: 1'b1, valid: 1'b1};
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (integer unsigned i = 0; i < 32; i++) begin
                rat_table[i] <= '{phys_reg: 6'(i), ready: 1'b1, valid: 1'b1};
            end
        end else if (flush) begin
            // Use the updated RRAT state (accounting for simultaneous commit)
            rat_table <= rrat_for_flush;        
        end else begin
            // Set ready for any CDB match
            for (integer unsigned i = 0; i < 32; i++) begin
                if ((cdb_alu_br_rat.valid && (rat_table[i].phys_reg == cdb_alu_br_rat.rd_paddr) && (5'(i) == cdb_alu_br_rat.rd_addr)) ||
                    (cdb_mul_div_rat.valid && (rat_table[i].phys_reg == cdb_mul_div_rat.rd_paddr) && (5'(i) == cdb_mul_div_rat.rd_addr)) ||
                    (cdb_mem_rat.valid && (rat_table[i].phys_reg == cdb_mem_rat.rd_paddr) && (5'(i) == cdb_mem_rat.rd_addr))) begin
                    rat_table[i].ready <= 1'b1;                
                end
            end

            // Write new allocation (overwrites ready if same address)
            if (rat_wen && (rat_waddr != 0)) begin
                rat_table[rat_waddr] <= rat_wdata;            
            end
        end
    end

    // Combinational read outputs for rename stage
    assign rat_rs1_rdata = rat_table[rat_rs1_raddr];
    assign rat_rs2_rdata = rat_table[rat_rs2_raddr];

    // Output full RAT for other modules that need it
    assign rat_out = rat_table;

endmodule : rat