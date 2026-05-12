module bp
import ooo_types::*;
#(
    parameter GHR_BITS = 8,
    parameter PHT_BITS = 8,
    parameter logic [1:0] PHT_INIT = 2'b01
) (
    input  logic                 clk,
    input  logic                 rst,

    // IF <-> BP
    input  logic [31:0]          if_pc,
    output logic                 pred_taken,
    output logic [1:0]           pht_counter,     // Output counter value for pipeline
    output logic [PHT_BITS-1:0]  pht_index,
    
    // BP <-> EX (via CDB)
    input  logic                 branch_done,
    input  logic                 branch_outcome,
    input  logic [PHT_BITS-1:0]  branch_index,
    input  logic [1:0]           branch_counter,  // Counter value from pipeline
    output logic                 bp_ready,
    output logic                 update_queue_full
);

    // GHR
    logic [GHR_BITS-1:0] ghr;

    // PHT datapath
    logic [1:0]           pht_rdata; 
    logic [1:0]           pht_counter_out;  // Final counter output (with forwarding)
    logic [PHT_BITS-1:0]  pht_index_d;

    // Dual-port SRAM controls (1 read + 1 write)
    logic                 r_csb;
    logic [PHT_BITS-1:0]  r_addr;
    logic [1:0]           r_dout;
    logic                 w_csb;
    logic [PHT_BITS-1:0]  w_addr;
    logic [1:0]           w_din;

    // Valid array signals - match SRAM timing structure
    logic                 valid_dout_reg;
    logic                 entry_valid;
    logic                 valid_array [2**PHT_BITS];  // Unpacked array
    // Registered inputs (match SRAM structure)
    logic [PHT_BITS-1:0]  valid_addr_r_reg;  // Read address register
    logic [PHT_BITS-1:0]  valid_addr_w_reg;  // Write address register
    logic                 valid_din_reg;     // Write data register
    logic                 valid_we_reg;      // Write enable register

    // Forwarding logic
    logic                 forwarding_match;
    logic [1:0]           forwarding_counter;

    // PHT Memory 
    // Port 0: Write, Port 1: Read
    bp_pht pht (
        .clk0   (clk),
        .csb0   (w_csb),
        .addr0  (w_addr),
        .din0   (w_din),
        .clk1   (clk),
        .csb1   (r_csb),
        .addr1  (r_addr),
        .dout1  (r_dout)
    );

    
    logic [7:0] pc_seg0;
    logic [7:0] pc_seg1;
    logic [7:0] ghr_fold;

    assign pc_seg0   = if_pc[9:2];                          // Lower 8 bits of PC
    assign pc_seg1   = {if_pc[17:12], if_pc[4:3]};        // Upper PC segment
    assign ghr_fold  = ghr[7:0] ^ {6'b0, ghr[9:8]};       // Fold upper 2 GHR bits into lower 8
    assign pht_index_d = pc_seg0 ^ pc_seg1 ^ ghr_fold;

    assign pred_taken  = pht_counter_out[1];
    assign pht_counter = pht_counter_out;
    assign pht_index   = pht_index_d;
    assign bp_ready    = 1'b1;  // Always ready for predictions
    assign update_queue_full = 1'b0;  // No queue needed anymore

    // Read port: always reading current prediction index
    assign r_csb  = 1'b0;
    assign r_addr = pht_index_d;

    // Write port: write directly when branch completes
    assign w_csb  = !branch_done;
    assign w_addr = branch_index;

    // Compute updated counter for incoming branch (for writing)
    always_comb begin
        if (branch_outcome) begin
            if (branch_counter == 2'b11)
                forwarding_counter = 2'b11;
            else
                forwarding_counter = branch_counter + 2'b01;
        end else begin
            if (branch_counter == 2'b00)
                forwarding_counter = 2'b00;
            else
                forwarding_counter = branch_counter - 2'b01;
        end
    end

    assign entry_valid = valid_dout_reg;

    // Use PHT_INIT for uninitialized entries, otherwise use SRAM data
    assign pht_counter_out = entry_valid ? pht_rdata : PHT_INIT;

    // Write data is the updated counter
    assign w_din = forwarding_counter;

    always_ff @(posedge clk) begin
        if (rst) begin
            ghr              <= '0;
            pht_rdata        <= PHT_INIT;
            valid_dout_reg   <= 1'b0;
            valid_addr_r_reg <= '0;
            valid_addr_w_reg <= '0;
            valid_din_reg    <= 1'b0;
            valid_we_reg     <= 1'b0;
            for (integer i = 0; i < 2**PHT_BITS; i++) begin
                valid_array[i] <= 1'b0;
            end
        end else begin
            // Stage 1: Register read address (always reading, like cache)
            valid_addr_r_reg <= pht_index_d;
            
            // Stage 1: Register write controls
            valid_addr_w_reg <= branch_index;
            valid_din_reg    <= 1'b1;  // Always writing valid=1
            valid_we_reg     <= branch_done;

            // Stage 2: Write to array using registered write inputs
            if (valid_we_reg) begin
                valid_array[valid_addr_w_reg] <= valid_din_reg;
            end

            // Stage 2: Read from array using registered read address (always reading)
            valid_dout_reg <= valid_array[valid_addr_r_reg];

            // Update pht_rdata from read port (already pipelined by SRAM)
            pht_rdata <= r_dout;

            // Update GHR when branch completes
            if (branch_done) begin
                ghr <= {ghr[GHR_BITS-2:0], branch_outcome};
            end
        end
    end

endmodule