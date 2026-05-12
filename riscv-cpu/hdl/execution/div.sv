module div 
import ooo_types::*;
(
    input  logic            clk,
    input  logic            rst,
    input  logic            flush,
    input  fu_div_pkt       div_pkt,

    output logic            div_complete,
    output cdb_mul_div_pkt  cdb_div
);

    logic divide_complete;
    logic [div_a_width-1:0] quotient, remainder, op_a, op_b;
    logic divide_by_0;
    
    // FSM state
    div_state_t state, next_state;

    assign div_complete = (state == COMPLETE);

    // FSM state register
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            state <= IDLE;
        end
        else begin
            state <= next_state;
        end
    end

    // FSM next state logic
    always_comb begin
        case (state)
            IDLE:     next_state = div_pkt.valid ? DIVIDING : IDLE;
            DIVIDING: next_state = divide_complete ? COMPLETE : DIVIDING;
            COMPLETE: next_state = IDLE;
            default:  next_state = IDLE;
        endcase
    end
    // Operand preparation based on signed/unsigned operation
    always_comb begin
        if (div_pkt.valid) begin
            unique case (div_pkt.div_op)
                div, rem: begin
                    // Sign-extend for signed operations
                    op_a = {div_pkt.op_a[31], div_pkt.op_a};
                    op_b = {div_pkt.op_b[31], div_pkt.op_b};
                end
                divu, remu: begin
                    // Zero-extend for unsigned operations
                    op_a = {1'b0, div_pkt.op_a};
                    op_b = {1'b0, div_pkt.op_b};
                end
            endcase
        end else begin
            op_a = '0;
            op_b = '0;
        end
    end

    // Instance of DW_div_seq
    DW_div_seq #(
        div_a_width, 
        div_b_width, 
        div_tc_mode, 
        div_num_cyc,
        div_rst_mode, 
        div_input_mode, 
        div_output_mode,
        div_early_start
    )
    sequential_divide_unit (
        .clk(clk),
        .rst_n(~rst),
        .hold('0),
        .start((state == IDLE || state == COMPLETE) && (next_state == DIVIDING) && div_pkt.valid),
        .a(op_a),
        .b(op_b),
        .complete(divide_complete),
        .divide_by_0(divide_by_0),
        .quotient(quotient),
        .remainder(remainder)
    );

    // CDB output logic
    always_comb begin
        cdb_div = '{default: '0};
        
        // Only broadcast result in COMPLETE state
        if (state == COMPLETE) begin
            unique case (div_pkt.div_op)
                div, divu: cdb_div.result = divide_by_0 ? 32'hFFFFFFFF : quotient[31:0];
                rem, remu: cdb_div.result = remainder[31:0];
                default:   cdb_div.result = '0;
            endcase

            cdb_div.valid     = 1'b1;
            cdb_div.rob_index = div_pkt.rob_index;
            cdb_div.rd_paddr  = div_pkt.rd_paddr;
            cdb_div.rd_addr   = div_pkt.rd_addr;
            cdb_div.rs1_val   = div_pkt.op_a;
            cdb_div.rs2_val   = div_pkt.op_b;
        end
    end

endmodule : div