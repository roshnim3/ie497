module arbiter #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64
) (
    input   logic               clk,
    input   logic               rst,
    input   logic               i_mem_flush,
    input   logic               d_mem_flush,

    // instruction adapter -> arb
    input   logic   [ADDR_WIDTH-1:0]  i_req_addr,
    input   logic               i_req_read,
    input   logic               i_req_write,
    input   logic   [DATA_WIDTH-1:0]      i_req_data,
    input   logic               i_req_done,

    output  logic   [DATA_WIDTH-1:0]      i_burst_data,
    output  logic               i_burst_valid,
    output  logic   [ADDR_WIDTH-1:0]  i_burst_addr,
    output logic i_arb_ready,

    // data adapter -> arb
    input   logic   [ADDR_WIDTH-1:0]  d_req_addr,
    input   logic               d_req_read,
    input   logic               d_req_write,
    input   logic   [DATA_WIDTH-1:0]      d_req_data,
    input   logic               d_req_done,

    output  logic   [DATA_WIDTH-1:0]      d_burst_data,
    output  logic               d_burst_valid,
    output  logic   [ADDR_WIDTH-1:0]  d_burst_addr,
    output logic d_arb_ready,

    // arb -> bmem
    output  logic   [ADDR_WIDTH-1:0]  bmem_addr,
    output  logic               bmem_read,
    output  logic               bmem_write,
    output  logic   [DATA_WIDTH-1:0]      bmem_wdata,
    input   logic               bmem_ready,
    input   logic   [ADDR_WIDTH-1:0]  bmem_raddr,
    input   logic   [DATA_WIDTH-1:0]      bmem_rdata,
    input   logic               bmem_rvalid
);
  
    // Combinational forwarding logic - data has priority over instruction
    always_comb begin
        // Priority: data > instruction
        if (d_req_read || d_req_write) begin
            // Data adapter request (has priority)
            bmem_addr  = d_req_addr;
            bmem_read  = d_req_read;
            bmem_write = d_req_write;
            bmem_wdata = d_req_data;
        end else if (i_req_read || i_req_write) begin
            // Instruction adapter request (no data conflict)
            bmem_addr  = i_req_addr;
            bmem_read  = i_req_read;
            bmem_write = i_req_write;
            bmem_wdata = i_req_data;
        end else begin
            // No requests
            bmem_read  = 1'b0;
            bmem_write = 1'b0;
            bmem_addr  = '0;
            bmem_wdata = '0;
        end
    end

    // Track which adapter made the last bmem request (for routing responses)
    // Store the address each adapter requested so we can verify responses
    logic [ADDR_WIDTH-1:0] last_i_addr, last_d_addr;
    
    // Track number of flushes to ignore corresponding bursts
    // logic [2:0] flush_count;  // Count pending flushes (max 7)
    // logic       rvalid_prev;  // Previous value of bmem_rvalid to detect edges
    // logic [ADDR_WIDTH-1:0] latched_raddr;  // Latched bmem_raddr for checking on falling edge
    
    always_ff @(posedge clk) begin
        if (rst) begin
            last_i_addr <= '0;
            last_d_addr <= '0;
            // flush_count <= '0;
            // rvalid_prev <= '0;
            // latched_raddr <= '0;
        end else begin
            // Handle flush - clear respective address tracking
            if (i_mem_flush) begin
                last_i_addr <= '0;
            end
            if (d_mem_flush) begin
                last_d_addr <= '0;
            end
            
            // // Track previous rvalid to detect falling edge (end of burst)
            // rvalid_prev <= bmem_rvalid;
            
            // // Latch the response address when rvalid is high
            // if (bmem_rvalid) begin
            //     latched_raddr <= bmem_raddr;
            // end
            if(i_req_done) begin
                // Instruction adapter completed request, clear tracking
                last_i_addr <= '0;
            end
            if(d_req_done) begin
                // Data adapter completed request, clear tracking
                last_d_addr <= '0;
            end

            if (bmem_ready) begin
                // Track the address each adapter sent to bmem based on priority
                if (d_req_read || d_req_write) begin
                    // Data adapter request is being forwarded
                    last_d_addr <= d_req_addr;                end else if (i_req_read || i_req_write) begin
                    // Instruction adapter request is being forwarded
                    last_i_addr <= i_req_addr;                end
            end
            
            // // Detect falling edge of rvalid (end of burst)
            // if (rvalid_prev && !bmem_rvalid) begin
            //     // Check the latched response address to determine what to do
            //     if (latched_raddr == last_d_addr && last_d_addr != '0) begin
            //         // Data burst just finished, clear pending request
            //         last_d_addr <= '0;
            //            //     end else if (flush_count > 0) begin
            //         // A burst just finished and we're ignoring it, decrement flush count
            //         flush_count <= flush_count - 3'd1;
            //            //     end else if (last_i_addr != '0) begin
            //         // Valid instruction burst just finished, clear pending request
            //         last_i_addr <= '0;
            //            //     end
            // end
        end
    end

    // Ready signals and data forwarding to adapters
    always_comb begin
        // Forward read data to the appropriate adapter based on address matching
        // Only route to instruction adapter if the response address matches its last request
        // AND we're not ignoring this beat due to a flush
        i_burst_valid = bmem_rvalid && (bmem_raddr == last_i_addr);// && (flush_count == 0);
        i_burst_data = bmem_rdata;
        i_burst_addr = bmem_raddr;
        // i_arb_ready: ready when bmem_ready AND no data request
        i_arb_ready = bmem_ready && !d_req_read && !d_req_write;
        
        // Only route to data adapter if the response address matches its last request
        d_burst_valid = bmem_rvalid && (bmem_raddr == last_d_addr);
        d_burst_data = bmem_rdata;
        d_burst_addr = bmem_raddr;
        d_arb_ready = bmem_ready;
    end

endmodule : arbiter