module mul
import ooo_types::*;
(
    input  logic            clk,
    input  logic            rst,
    input  logic            flush,
    input  fu_mul_pkt       mul_pkt,

    output cdb_mul_div_pkt  cdb_mul
);
    logic [mult_a_width + mult_b_width -1:0] product;
    logic tc;

    logic [mult_a_width-1:0] multiplier;
    logic [mult_b_width-1:0] multiplicand;

    fu_mul_pkt [mult_num_stages-2:0] mul_pkt_pipeline;

    // Operand preparation based on signed/unsigned operation
    always_comb begin
        // Default: unsigned multiplication
        tc = 1'b0;
        multiplicand = {1'b0, mul_pkt.op_a};
        multiplier = {1'b0, mul_pkt.op_b};

        if (mul_pkt.valid) begin
            unique case (mul_pkt.mul_op)
                mul, mulh: begin
                    // Signed × Signed
                    tc = 1'b1;
                    multiplicand = {mul_pkt.op_a[31], mul_pkt.op_a};
                    multiplier   = {mul_pkt.op_b[31], mul_pkt.op_b};
                end
                mulhsu: begin
                    // Signed × Unsigned
                    tc = 1'b1;
                    multiplicand = {mul_pkt.op_a[31], mul_pkt.op_a};
                    multiplier   = {1'b0, mul_pkt.op_b};
                end
                mulhu: begin
                    // Unsigned × Unsigned (use defaults)
                    tc = 1'b0;
                    multiplicand = {1'b0, mul_pkt.op_a};
                    multiplier   = {1'b0, mul_pkt.op_b};
                end
            endcase
        end
    end

    // Meta data pipeline
    always_ff @ (posedge clk) begin
        if (rst || flush) begin
            mul_pkt_pipeline <= '0;
        end else begin
            mul_pkt_pipeline <= {mul_pkt, mul_pkt_pipeline[mult_num_stages-2:1]};
        end
    end

    DW_mult_pipe #(
        mult_a_width, 
        mult_b_width, 
        mult_num_stages,
        mult_stall_mode, 
        mult_rst_mode, 
        mult_op_iso_mode
    )
    pipelined_multiplier_unit (.clk(clk),
        .rst_n(~rst),
        .en(mul_pkt.valid),
        .tc(tc),
        .a(multiplier),
        .b(multiplicand),
        .product(product) 
    );

    // CDB output logic - select correct 32 bits based on operation
    always_comb begin
        cdb_mul = '{default:'0};

        if (mul_pkt_pipeline[0].valid) begin
            // mul returns lower 32 bits, all others return upper 32 bits
            unique case (mul_pkt_pipeline[0].mul_op)
                mul:                cdb_mul.result = product[31:0];
                mulh, mulhsu, mulhu: cdb_mul.result = product[63:32];
                default:            cdb_mul.result = '0;
            endcase

            cdb_mul.valid     = 1'b1;
            cdb_mul.rob_index = mul_pkt_pipeline[0].rob_index;
            cdb_mul.rd_paddr  = mul_pkt_pipeline[0].rd_paddr;
            cdb_mul.rd_addr   = mul_pkt_pipeline[0].rd_addr;
            cdb_mul.rs1_val   = mul_pkt_pipeline[0].op_a;
            cdb_mul.rs2_val   = mul_pkt_pipeline[0].op_b;
        end
    end

endmodule : mul