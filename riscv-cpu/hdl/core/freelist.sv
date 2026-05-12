module freelist 
import ooo_types::*;
(
    input logic        clk,
    input logic        rst,
    input logic        flush,
    input rob_commit_pkt [1:0]  rob_commit,
    input logic        alloc_req,
    input logic [1:0]       free_req,
    input logic [1:0][5:0]  free_reg,
    input rat_entry_t  rrat [31:0],
    
    output logic [5:0] alloc_reg,
    output logic       full,
    output logic       empty
);

    logic [63:0] free_list, rebuilt_list;
    
    // P0-P31 are initially allocated to architectural registers x0-x31 (identity mapping)
    // After initial allocation, all registers P1-P63 can be used for renaming (P0 reserved for x0)
    localparam ALL_FREE = 64'hFFFF_FFFF_FFFF_FFFE;
    localparam INITIAL_FREE = 64'hFFFF_FFFF_0000_0000;  // Only P32-P63 are free initially

    assign empty = (free_list == 64'h0);
    assign full  = (free_list == ALL_FREE);

    // Find first free physical register for allocation
    always_comb begin
        alloc_reg = '0;
        for (integer unsigned i = 1; i < 64; i++) begin  // Start at 1 (skip P0 which is always x0)
            if (free_list[i]) begin
                alloc_reg = 6'(i);
                break;
            end
        end
    end

    // Rebuild freelist from RRAT on flush (marks allocated registers as not free)
    always_comb begin
        rebuilt_list = ALL_FREE;
        for (integer unsigned i = 0; i < 32; i++) begin
            if (rrat[i].valid) begin
                // Mark RRAT physical register as allocated, UNLESS it's being replaced
                // by the committing instruction (in which case it should be freed)
                if (!(rob_commit[0].valid && (5'(i) == rob_commit[0].rd_addr))) begin
                    rebuilt_list[rrat[i].phys_reg] = 1'b0;
                end
                if (!(rob_commit[1].valid && (5'(i) == rob_commit[1].rd_addr))) begin
                    rebuilt_list[rrat[i].phys_reg] = 1'b0;
                end
            end
        end
        // Also mark the committing instruction's physical register as allocated
        // This handles the case where we flush on commit and the RAT is updated
        // with the new mapping before RRAT
        if (rob_commit[0].valid && (rob_commit[0].rd_addr != 5'd0)) begin
            rebuilt_list[rob_commit[0].rd_paddr] = 1'b0;
        end
        if (rob_commit[1].valid && (rob_commit[1].rd_addr != 5'd0)) begin
            rebuilt_list[rob_commit[1].rd_paddr] = 1'b0;
        end
    end

    // Freelist update logic
    always_ff @(posedge clk) begin
        if (rst) begin
            free_list <= INITIAL_FREE;
        end else if (flush) begin
            free_list <= rebuilt_list;
        end else begin
            // Allocate: mark first free register as allocated
            if (alloc_req) begin
                for (integer unsigned i = 1; i < 64; i++) begin  // Start at 1 (skip P0)
                    if (free_list[i]) begin
                        free_list[i] <= 1'b0;
                        break;
                    end
                end
            end
            
            // Free: mark register as available (unless it's P0)
            if (free_req[0] && (free_reg[0] != 6'd0)) begin
                free_list[free_reg[0]] <= 1'b1;
            end
            if (free_req[1] && (free_reg[1] != 6'd0)) begin
                free_list[free_reg[1]] <= 1'b1;
            end
        end
    end
    
endmodule