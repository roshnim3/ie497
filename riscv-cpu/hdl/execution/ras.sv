module ras
import ooo_types::*;
#(
    parameter RAS_SIZE = 8
) (
    input  logic                 clk,
    input  logic                 rst,

    // Decode stage signals
    input  logic                 is_call,       // Call instruction detected
    input  logic                 is_return,     // Return instruction detected
    input  logic [31:0]          decode_pc,     // Current PC from fetch (for computing return address)
    
    // Branch mispredict recovery
    input  logic                 br_mispredict, // Branch misprediction signal (flush RAS on mispredict)

    // RAS prediction output
    output logic [31:0]          ras_target,    // Predicted return address
    output logic                 ras_valid      // RAS prediction valid (only high when returning)
);

    // Internal control signals
    logic        push, pop;
    logic [31:0] push_addr;
    
    // Stack signals
    logic [31:0] stack_dout;
    logic        stack_full;
    logic        stack_empty;
    
    // Push/pop control logic
    assign push = is_call && !stack_full;  
    assign pop = is_return;
    assign push_addr = decode_pc + 32'd4;  // Return address is PC + 4 
    

    // RAS prediction output
    assign ras_target = stack_dout;
    assign ras_valid = is_return && !stack_empty;

    // Instantiate the stack module
    stack #(
        .DATA_WIDTH(32),
        .STACK_SIZE(RAS_SIZE)
    ) ras_stack (
        .clk        (clk),
        .rst        (rst),
        .flush      (br_mispredict),  // Flush stack on branch mispredict (simple recovery)
        .push       (push),
        .pop        (pop),
        .din        (push_addr),
        .dout       (stack_dout),
        .full       (stack_full),
        .empty      (stack_empty)
    );
    
endmodule : ras
