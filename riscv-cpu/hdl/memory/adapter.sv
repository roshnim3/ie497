module adapter #(
    parameter IS_ICACHE = 0  // 1 for I-cache adapter, 0 for D-cache adapter
)(
    input   logic           clk,
    input   logic           rst,
    input   logic           flush,

    // cache side signals
    input   logic   [31:0]  cache_addr,
    input   logic           cache_read,
    input   logic           cache_write,
    input   logic   [255:0] cache_wdata,

    output  logic   [255:0] cache_rdata,
    output  logic           cache_resp,

    // arbitrator side signals
    input   logic   [31:0]  burst_addr,
    input   logic           burst_valid,
    input   logic   [63:0]  burst_rdata,

    output  logic   [31:0]  arb_addr,
    output  logic           arb_read,
    output  logic           arb_write,
    output  logic   [63:0]  arb_wdata,
    output  logic           req_done,
    input   logic           arb_ready
);

    // Just to remove unused signal warnings
    logic dummy;
    assign dummy = burst_addr==cache_addr;

    assign arb_addr = cache_addr;

    logic cache_resp_next;
    logic [255:0] rdata, rdata_next;

    assign cache_rdata = rdata;

    enum logic [2:0] {
            DATA_1 = 3'b000, // Waiting for first data burst for a read or setting the first burst for a write
            DATA_2 = 3'b001, // Waiting for second data burst for a read or setting the second burst for a write
            DATA_3 = 3'b010, // Waiting for third data burst for a read or setting the third burst for a write
            DATA_4 = 3'b011  // Waiting for fourth data burst for a read or setting the fourth burst for a write
        } state, next_state;
    
    assign arb_write = arb_ready ? cache_write : '0;

    // For the testbench the read signal needs to be latched here for the FSM to move
    // dont need this block for actual synthesis and full system
    logic cache_read_pulse;
    always_ff @(posedge clk) begin
        if (state == DATA_4 || rst || flush) begin
            cache_read_pulse <= 1'b0;
        end else if (arb_ready && !cache_read_pulse && cache_read) begin
            cache_read_pulse <= 1'b1;
        end
    end
    assign arb_read = arb_ready && cache_read && !cache_read_pulse && !flush;
    assign req_done = state[2];

    always_ff @(posedge clk) begin
        if(rst) begin
            cache_resp <= '0;
            state <= DATA_1;
            
        end else if (flush) begin
            // On flush, reset to DATA_1 and clear response to abort ongoing request
            cache_resp <= '0;
            state <= DATA_1;
        end else begin
            cache_resp <= cache_resp_next;
            rdata <= rdata_next;
            state <= next_state;
        end
    end

    always_comb begin
        cache_resp_next = '0;
        rdata_next = rdata;
        next_state = !burst_valid && cache_read ? DATA_1 : state;
        arb_wdata = '0;  // Default assignment

        // If no active transaction, go to DATA_1
        case (state)
            DATA_1:
                if (burst_valid && cache_read) begin // Use latched read signal for testbench otherwise use cache_read
                    rdata_next[63:0] = burst_rdata;
                    next_state = DATA_2;                end
                else if (cache_write && arb_ready) begin
                    arb_wdata = cache_wdata[63:0];
                    next_state = DATA_2;                end
            DATA_2:
                if (burst_valid && cache_read) begin // Use latched read signal for testbench otherwise use cache_read
                    rdata_next[127:64] = burst_rdata;
                    next_state = DATA_3;
                end
                else if (cache_write && arb_ready) begin
                    arb_wdata = cache_wdata[127:64];
                    next_state = DATA_3;
                end
            DATA_3:
                if (burst_valid && cache_read) begin // Use latched read signal for testbench otherwise use cache_read
                    rdata_next[191:128] = burst_rdata;
                    next_state = DATA_4;
                end
                else if (cache_write && arb_ready) begin
                    arb_wdata = cache_wdata[191:128];
                    next_state = DATA_4;
                end
            DATA_4:
                if (burst_valid && cache_read) begin // Use latched read signal for testbench otherwise use cache_read
                    rdata_next[255:192] = burst_rdata;
                    next_state = DATA_1;
                    cache_resp_next = '1;                
                end
                else if (cache_write && arb_ready) begin
                    arb_wdata = cache_wdata[255:192];
                    next_state = DATA_1;
                    cache_resp_next = '1;                
                end
        endcase
    end
endmodule : adapter