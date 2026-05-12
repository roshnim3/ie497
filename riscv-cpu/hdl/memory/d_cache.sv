module d_cache (
    input   logic           clk,
    input   logic           rst,
    input   logic           flush,
    input   logic           stage_flush,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic   [3:0]   ufp_rmask,
    input   logic   [3:0]   ufp_wmask,
    output  logic   [31:0]  ufp_rdata,
    input   logic   [31:0]  ufp_wdata,
    output  logic           ufp_resp,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp,
    
    // Busy signal - high when cache is doing writeback and cannot be flushed
    output  logic           busy
);
    enum logic [2:0] {
        IDLE,
        HIT,
        ALLOCATE,
        WRITEBACK
    } state, next_state;

    // registers
    logic [31:0] mem_addr;
    logic [3:0] mask;
    logic write;
    logic [31:0] mem_wdata;
    logic [3:0] evict, evict_next;            // one-hot encoding of which way to evict
    logic [31:0] dfp_addr_reg, dfp_addr_reg_next;
    logic [255:0] dfp_wdata_reg, dfp_wdata_reg_next;
    always_ff @(posedge clk ) begin
        if (rst) begin
            mem_addr <= 32'b0;
            mask <= 4'b0;
            write <= 1'b0;
            mem_wdata <= 32'b0;
            evict <= 4'b0;
            state <= IDLE;

            dfp_addr_reg <= 32'b0;
            dfp_wdata_reg <= 256'b0;
        end else if (flush) begin
            // On flush, reset state to IDLE to abort any ongoing memory request
            state <= IDLE;
        end else begin
            state <= next_state;
            // only update these registers when transitioning from IDLE to active
            if (state == IDLE && (ufp_rmask != 4'b0 || ufp_wmask != 4'b0)) begin
                mem_addr <= ufp_addr;
                mask <= ufp_rmask | ufp_wmask;
                write <= |ufp_wmask;
                mem_wdata <= ufp_wdata;            end
            if (state == HIT) begin
                evict <= evict_next;
                if (next_state == WRITEBACK) begin
                    dfp_addr_reg <= dfp_addr_reg_next;
                    dfp_wdata_reg <= dfp_wdata_reg_next;
                end
            end
        end
    end

    // wires for modules
    logic [3:0] csb;                // chip select bars for 4 ways
    logic [3:0] web;                // write enable bars for 4 ways
    logic [31:0]  wmask [3:0];        // write masks for 4 ways
    logic [3:0] array_addr;               // same address for all arrays
    logic [255:0] data_din;          // dont need 4 copies of din, same for all arrays
    logic [255:0] data_dout [3:0];    // data out for 4 ways
    logic [22:0] tag_din;           // dont need 4 copies of din, same for all arrays
    logic [22:0] tag_dout [3:0];     // tag out for 4 ways
    logic valid_din;            // whether to set valid 
    logic [3:0] valid_dout;         // whether each way is valid
    logic dirty_din;            // whether to set dirty 
    logic [3:0] dirty_dout;         // dirty for 4 ways

    logic lru_csb;                  // chip select bar for lru array
    logic lru_web;                  // write enable for lru array
    logic [3:0] lru_addr;           // address for lru array
    logic [2:0] lru_din;            // data in for lru array
    logic [2:0] lru_dout;           // data out for lru array

    // intermediate logic
    logic [255:0] mem_data;        // data read from cache line
    logic [255:0] temp_data;
    logic [31:0] mem_wmask;       // write mask for memory
    logic [22:0] tag_addr;        // tag address for memory
    logic valid;                  // whether the current access is valid (read or write)
    logic [3:0] hit_way;
    
    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       (csb[i]),
            .web0       (web[i]),
            .wmask0     (wmask[i]),
            .addr0      (array_addr),
            .din0       (data_din),
            .dout0      (data_dout[i])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk),
            .csb0       (csb[i]),
            .web0       (web[i]),
            .addr0      (array_addr),
            .din0       (tag_din),
            .dout0      (tag_dout[i])
        );
        sp_ff_array valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (csb[i]),
            .web0       (web[i]),
            .addr0      (array_addr),
            .din0       (valid_din),
            .dout0      (valid_dout[i])
        );
        sp_ff_array dirty_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (csb[i]),
            .web0       (web[i]),
            .addr0      (array_addr),
            .din0       (dirty_din),
            .dout0      (dirty_dout[i])
        );
    end endgenerate

    sp_ff_array #(
        .WIDTH      (3)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       (lru_csb),
        .web0       (lru_web),
        .addr0      (lru_addr),
        .din0       (lru_din),
        .dout0      (lru_dout)
    );

    assign  hit_way = {(tag_dout[3] == mem_addr[31:9] && valid_dout[3]),
                      (tag_dout[2] == mem_addr[31:9] && valid_dout[2]),
                      (tag_dout[1] == mem_addr[31:9] && valid_dout[1]),
                      (tag_dout[0] == mem_addr[31:9] && valid_dout[0])};

    assign  mem_data = (hit_way[0] ? data_dout[0] : 
                        hit_way[1] ? data_dout[1] : 
                        hit_way[2] ? data_dout[2] : 
                        hit_way[3] ? data_dout[3] : '0);


    // PLRU magic logic
    always_comb begin
        casez (lru_dout) // L0 L1 L2
            3'b00?: evict_next = 4'b1000; // LRU was D 
            3'b01?: evict_next = 4'b0100;
            3'b1?0: evict_next = 4'b0010;
            3'b1?1: evict_next = 4'b0001; 
            default: evict_next = 4'b0001; 
        endcase
    end

    always_comb begin
        ufp_rdata = 32'b0;
        ufp_resp = 1'b0;
        dfp_addr = (state == ALLOCATE) ? mem_addr & 32'hFFFFFFE0 : (state == WRITEBACK) ? dfp_addr_reg : 'X;  
        dfp_read = (state == ALLOCATE && !dfp_resp && !flush) ? 1'b1 : 1'b0;
        dfp_write = (state == WRITEBACK && !dfp_resp) ? 1'b1 : 1'b0;
        dfp_wdata = (state == WRITEBACK) ? dfp_wdata_reg : 256'b0;
        
        // Indicate cache is busy during writeback - cannot be flushed
        busy = (state == WRITEBACK);
        
        next_state = state;
        csb = 4'b1111; // actuve low ???
        web = 4'b1111; // active low - disable writes to all ways
        wmask = '{default: '0};
        data_din = 256'b0;
        tag_din = 23'b0;
        valid_din = 1'b0;
        dirty_din = 1'b0;
        lru_csb = 1'b1;
        lru_web = 1'b1;
        lru_addr = 4'b0000;
        lru_din = 3'b0;
        array_addr = 4'b0000;

        dfp_addr_reg_next  = dfp_addr_reg;
        dfp_wdata_reg_next = dfp_wdata_reg;

        case (state)
            IDLE: begin
                next_state = (ufp_rmask != 4'b0 || ufp_wmask != 4'b0) ? HIT : IDLE;
                array_addr = ufp_addr[8:5];
                csb = 4'b0000;
                lru_csb = 1'b0;
                lru_addr = ufp_addr[8:5];
            end
            HIT: begin
                array_addr = mem_addr[8:5];  // Ensure array address is set correctly
                if (|hit_way) begin // if there is a cache hit
                    next_state = IDLE;
                    ufp_resp = 1'b1;                    lru_csb = 1'b0;
                    lru_web = 1'b0;
                    lru_addr = mem_addr[8:5];
                    lru_din = (hit_way[0] ? {1'b0, lru_dout[1], 1'b0} : 
                                hit_way[1] ? {1'b0, lru_dout[1], 1'b1} :
                                hit_way[2] ? {1'b1, 1'b0, lru_dout[0]} : {1'b1, 1'b1, lru_dout[0]});

                    if (!write) begin // on read, send out read data after mask applied
                        ufp_rdata = {mask[3] ? mem_data[32 * mem_addr[4:2] + 24 +: 8] : 8'b0,
                                    mask[2] ? mem_data[32 * mem_addr[4:2] + 16 +: 8] : 8'b0,
                                    mask[1] ? mem_data[32 * mem_addr[4:2] + 8  +: 8] : 8'b0,
                                    mask[0] ? mem_data[32 * mem_addr[4:2]      +: 8] : 8'b0};
                    end else begin // on a write
                        csb = ~hit_way; // active low - enable the hitting way
                        web = ~hit_way; // active low - enable writes to hitting way
                        mem_wmask = {28'b0, mask} << mem_addr[4:0]; // highlight the bytes we wanna write to
                        wmask = { hit_way[3] ? mem_wmask : 32'b0,
                                  hit_way[2] ? mem_wmask : 32'b0,
                                  hit_way[1] ? mem_wmask : 32'b0,
                                  hit_way[0] ? mem_wmask : 32'b0 }; // select the way we want to write to
                        data_din = 256'b0;
                        data_din[mem_addr[4:2]*32 +: 32] = mem_wdata;
                        dirty_din = 1'b1;    // set dirty on write
                        valid_din = 1'b1;    // set valid on write
                        tag_din = mem_addr[31:9]; // keep tag as is on write
                    end
                end else begin 
                    if (|(dirty_dout & evict_next)) begin
                        next_state = WRITEBACK;                        tag_addr = (evict_next[0] ? tag_dout[0] : '0) |   
                                   (evict_next[1] ? tag_dout[1] : '0) |
                                   (evict_next[2] ? tag_dout[2] : '0) |
                                   (evict_next[3] ? tag_dout[3] : '0);
                        dfp_addr_reg_next = {tag_addr, mem_addr[8:5], 5'b00000};
                        dfp_wdata_reg_next = (evict_next[0] ? data_dout[0] : 256'b0) |
                                    (evict_next[1] ? data_dout[1] : 256'b0) |
                                    (evict_next[2] ? data_dout[2] : 256'b0) |
                                    (evict_next[3] ? data_dout[3] : 256'b0);
                    end else begin
                        next_state = ALLOCATE;                    end
                end
            end
            ALLOCATE: begin
                next_state = (dfp_resp == 1'b1) ? IDLE : ALLOCATE;                if(dfp_resp == 1'b1) begin // turn off read once response is received
                    csb = ~evict; // active low - enable the evicted way
                    web = ~evict; // active low - enable writes to evicted way
                    array_addr = mem_addr[8:5];
                    valid_din = 1'b1;    // set valid on allocate
                    tag_din = mem_addr[31:9]; // update tag on allocate
                    mem_wmask = '1;
                    wmask = { evict[3] ? mem_wmask : 32'b0,
                                  evict[2] ? mem_wmask : 32'b0,
                                  evict[1] ? mem_wmask : 32'b0,
                                  evict[0] ? mem_wmask : 32'b0 };
                    data_din = dfp_rdata;
                    dirty_din = 1'b0;    // clear dirty on read allocate
                end
            end
            WRITEBACK: begin
                next_state = (dfp_resp == 1'b1) ? ALLOCATE : WRITEBACK;            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule
