module stack #(
    parameter DATA_WIDTH = 32,
    parameter STACK_SIZE = 16 
) (
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    flush,
    input  logic                    push,  
    input  logic                    pop,   
    input  logic [DATA_WIDTH-1:0]   din,   

    output logic [DATA_WIDTH-1:0]   dout,  
    output logic                    full,  
    output logic                    empty  
); 

    logic [$clog2(STACK_SIZE):0] tos; 
    logic [DATA_WIDTH-1:0] data [STACK_SIZE]; 

    assign empty = (tos == '0);
    assign full  = (tos == STACK_SIZE[$clog2(STACK_SIZE):0]);
    
    assign dout = empty ? '0 : data[tos - 1'b1];
    
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            tos <= '0;
        end else begin
            // Push: add element to top and increment pointer
            if (push && !pop && !full) begin
                data[tos] <= din;
                tos <= tos + ($clog2(STACK_SIZE)+1)'(1);
            end 
            // Pop: just decrement pointer (data remains but is inaccessible)
            else if (pop && !push && !empty) begin
                tos <= tos - ($clog2(STACK_SIZE)+1)'(1);
            end
            // Simultaneous push and pop: replace top element, tos unchanged
            else if (push && pop && !empty) begin
                data[tos - 1] <= din;
            end
            // Push when empty with simultaneous pop: just push
            else if (push && pop && empty) begin
                data[0] <= din;
                tos <= ($clog2(STACK_SIZE)+1)'(1);
            end
        end
    end
    
endmodule