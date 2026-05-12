module  queue #(
    parameter DATA_WIDTH = 32,
    parameter QUEUE_SIZE = 16 // Keep QUEUE_SIZE as power of 2
) (
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    flush,
    input  logic                    enq, // Enqueue signal
    input  logic                    deq, // Dequeue signal
    input  logic [DATA_WIDTH-1:0]   din, // Data input

    output logic [DATA_WIDTH-1:0]   dout, // Data output
    output logic                    full, // Full signal
    output logic                    empty // Empty signal
); 

    // Doing ADDR_WIDTH instead of ADDR_WIDTH-1
    // to differentiate full and empty states with
    // the overflow indications are head[ADDR_WIDTH] and tail[ADDR_WIDTH]
    logic [$clog2(QUEUE_SIZE) : 0] head, tail; 
    logic [DATA_WIDTH - 1 : 0] data [QUEUE_SIZE]; // Data Storage

    // Logic for Empty
    assign empty = (head == tail);

    // Logic for Full
    assign full  = (head[$clog2(QUEUE_SIZE) - 1 : 0] == tail[$clog2(QUEUE_SIZE) - 1 : 0]) && 
                   (head[$clog2(QUEUE_SIZE)] != tail[$clog2(QUEUE_SIZE)]);
    
    // Data Output
    assign dout = empty ? '0 : data[head[$clog2(QUEUE_SIZE) - 1 : 0]];
    
    always_ff @(posedge clk) begin
        if (rst) begin // Synchronous Reset
            head <= '0;
            tail <= '0;
            data <= '{default:'0};
        end else if (flush) begin
            head <= '0;
            tail <= '0;
        end else begin
            if (enq && !full) begin
                data[tail[$clog2(QUEUE_SIZE) - 1 : 0]] <= din; // Store data at tail position
                tail <= tail + ($clog2(QUEUE_SIZE))'(1);     // Increment tail pointer
            end
            if (deq && !empty) begin
                head <= head + ($clog2(QUEUE_SIZE))'(1);      // Increment head pointer
            end
        end
    end
    
endmodule