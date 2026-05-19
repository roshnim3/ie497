module prf (
    input logic        clk,
    input logic        rst,

    // TODO: Need to add more ports for other functional units

    // BR ports (read only - write through combined alu_br port)
    input logic  [5:0]      br_ps1_addr,
    input logic  [5:0]      br_ps2_addr,
    output logic [31:0]     br_pr1_data,
    output logic [31:0]     br_pr2_data,

    // ALU ports (read only - write through combined alu_br port)
    input logic  [5:0]      alu_ps1_addr,
    input logic  [5:0]      alu_ps2_addr,
    output logic [31:0]     alu_pr1_data,
    output logic [31:0]     alu_pr2_data,

    // ALU_BR shared write port (from combined CDB)
    input logic  [5:0]      alu_br_pd_addr,
    input logic             alu_br_pd_wen,
    input logic [31:0]      alu_br_pd_wdata,

    // Shared custom-FU write port (fetch_trade, pkt_tx — retains the
    // mul_div_* naming from the RV32M era to minimize diff noise)
    input logic  [5:0]      mul_div_pd_addr,
    input logic             mul_div_pd_wen,
    input logic [31:0]      mul_div_pd_wdata,

    // MEM ports (read)
    input logic  [5:0]      mem_ps1_addr,
    input logic  [5:0]      mem_ps2_addr,
    output logic [31:0]     mem_pr1_data,
    output logic [31:0]     mem_pr2_data,

    // MEM write port (from CDB)
    input logic  [5:0]      mem_pd_addr,
    input logic             mem_pd_wen,
    input logic [31:0]      mem_pd_wdata,

    // PKT_TX read port (rs1 only — pkt_w/pkt_s have one source operand)
    input logic  [5:0]      pt_ps1_addr,
    output logic [31:0]     pt_pr1_data
);

    logic [31:0] registers[63:0];

    // Register file write logic - handle writes from all functional units
    always_ff @(posedge clk) begin
        if (rst) begin
            registers <= '{default: '0};
        end else begin
            // Multiple writes can happen simultaneously to different registers
            if (alu_br_pd_wen && (alu_br_pd_addr != 0)) begin
                registers[alu_br_pd_addr] <= alu_br_pd_wdata;
            end
            if (mul_div_pd_wen && (mul_div_pd_addr != 0)) begin
                registers[mul_div_pd_addr] <= mul_div_pd_wdata;
            end
            if (mem_pd_wen && (mem_pd_addr != 0)) begin
                registers[mem_pd_addr] <= mem_pd_wdata;
            end
        end
    end

    // Asynchronous reads for all functional units
    assign br_pr1_data  = registers[br_ps1_addr];
    assign br_pr2_data  = registers[br_ps2_addr];
    assign alu_pr1_data = registers[alu_ps1_addr];
    assign alu_pr2_data = registers[alu_ps2_addr];
    assign mem_pr1_data = registers[mem_ps1_addr];
    assign mem_pr2_data = registers[mem_ps2_addr];
    assign pt_pr1_data  = registers[pt_ps1_addr];

endmodule : prf