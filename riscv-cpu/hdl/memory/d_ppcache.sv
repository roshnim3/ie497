module d_ppcache 
#
(
    parameter NWAYS = 4,
    parameter NSETS = 16
)
(
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic   [3:0]   ufp_rmask,
    input   logic   [3:0]   ufp_wmask,
    output  logic   [31:0]  ufp_rdata,
    input   logic   [31:0]  ufp_wdata,
    output  logic           ufp_resp,
    output  logic           cache_ready,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp,

    input   logic           flush,
    input   logic           stage_flush,
    output  logic           busy
);
    // wires for modules
    logic [NWAYS-1:0] tv_web, dd_web;     // write enable bars for 4 ways
    logic [31:0]  wmask [NWAYS-1:0];        // write masks for 4 ways
    logic [$clog2(NSETS)-1:0] array_addr;               // same address for all arrays
    logic [$clog2(NSETS)-1:0] tv_addr;
    logic [$clog2(NSETS)-1:0] lru_addr;
    logic [255:0] data_din;          // dont need 4 copies of din, same for all arrays
    logic [255:0] data_dout [NWAYS-1:0];    // data out for 4 ways
    logic [27-$clog2(NSETS)-1:0] tag_din;           // dont need 4 copies of din, same for all arrays
    logic [27-$clog2(NSETS)-1:0] tag_dout [NWAYS-1:0];     // tag out for 4 ways
    logic valid_din;            // whether to set valid 
    logic [NWAYS-1:0] valid_dout;         // whether each way is valid
    logic dirty_din;            // whether to set dirty 
    logic [NWAYS-1:0] dirty_dout;         // dirty for 4 ways
    logic [NWAYS-1:0] data_csb;

    logic lru_web;                  // write enable for lru array
    logic lru_csb;

    localparam integer LRU_W = (NWAYS > 1) ? (NWAYS - 1) : 1;
    logic [LRU_W-1:0] lru_din;            
    logic [LRU_W-1:0] lru_dout; 

    generate for (genvar i = 0; i < NWAYS; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       (data_csb[i]), 
            .web0       (dd_web[i]),
            .wmask0     (wmask[i]),
            .addr0      (array_addr),
            .din0       (data_din),
            .dout0      (data_dout[i])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk),
            .csb0       ('0),  // always selected
            .web0       (tv_web[i]),
            .addr0      (tv_addr),
            .din0       (tag_din),
            .dout0      (tag_dout[i])
        );
        sp_ff_array valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       ('0),  // always selected
            .web0       (tv_web[i]),
            .addr0      (tv_addr),
            .din0       (valid_din),
            .dout0      (valid_dout[i])
        );
        sp_ff_array dirty_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       ('0),  // always selected
            .web0       (dd_web[i]),
            .addr0      (array_addr),
            .din0       (dirty_din),
            .dout0      (dirty_dout[i])
        );
    end endgenerate

    plru_array #(
        .WIDTH      (LRU_W)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       (lru_csb),  // always selected
        .web0       (lru_web),
        .addr0      (lru_addr),
        .din0       (lru_din),
        .dout0      (lru_dout)
    );

    typedef struct packed {
        logic [27-$clog2(NSETS)-1:0] tag;    // bits [31:9]
        logic [$clog2(NSETS)-1:0]  index;  // bits [8:5] 
        logic [4:0]  offset; // bits [4:0]
        logic [3:0]  mask;
        logic        write;
        logic [31:0] data;
        logic        valid;
    } stage_t;
    
    stage_t s1, s0;
    logic stall;

    localparam integer IDX_W = (NWAYS > 1) ? $clog2(NWAYS) : 1;
    logic [IDX_W-1:0] hit_way, evict_way;
    logic hit;
    logic [NWAYS-1:0] hit_vec, evict_vec; 

    logic [IDX_W:0] cmp_lhs;
    logic [IDX_W:0] cmp_rhs;

    always_ff @(posedge clk) begin
        if (rst) begin
            s1 <= '0;
            s0 <= '0;
        end else if (stage_flush) begin
            s1 <= '0;
        end else if (!stall) begin
            s1.tag <= ufp_addr[31:$clog2(NSETS)+5];
            s1.index <=  ufp_addr[$clog2(NSETS)+4:5];
            s1.offset <= ufp_addr[4:0];
            s1.mask <= ufp_wmask | ufp_rmask;
            s1.write <= |ufp_wmask;
            s1.data  <= ufp_wdata;
            s1.valid <= |ufp_rmask || |ufp_wmask;
        end else if(stall && hit) begin
            s1.valid <= 1'b0; 
        end
    end    

    // assign cache_ready = (s1.valid && (!hit || (s1.valid && s1.write && hit && (ufp_rmask != 4'b0)))) ? 1'b0 : 1'b1;
    
    assign stall = s1.valid && (!hit || (s1.write && hit && (ufp_rmask != 4'b0)));
    
    assign cache_ready = ~stall;

    
    assign hit = s1.valid && |hit_vec;

    // assign hit_vec = {(tag_dout[3] == s1.tag && valid_dout[3]),
    //                   (tag_dout[2] == s1.tag && valid_dout[2]),
    //                   (tag_dout[1] == s1.tag && valid_dout[1]),
    //                   (tag_dout[0] == s1.tag && valid_dout[0])};

    // assign hit_way = hit_vec[3] ? 2'd3 :
    //                  hit_vec[2] ? 2'd2 :
    //                  hit_vec[1] ? 2'd1 :
    //                  hit_vec[0] ? 2'd0 : 2'd0;

    always_comb begin
        for (integer i = 0; i < NWAYS; i++) begin
            hit_vec[i] = (tag_dout[i] == s1.tag) && valid_dout[i];
        end
    end
    
    always_comb begin
        hit_way = '0;
        for (integer unsigned i = 0; i < NWAYS; i++) begin
            if (hit_vec[i]) begin
                hit_way = (IDX_W)'(i);
            end
        end
    end

    always_comb begin
        evict_way = '0;
        for (integer unsigned i = 0; i < NWAYS; i++) begin
            if (evict_vec[i]) begin
                evict_way = (IDX_W)'(i);
            end
        end
    end

    logic[$clog2(NWAYS):0] node;
    logic[$clog2(NWAYS):0] base;
    logic[$clog2(NWAYS):0] span;
    generate
        if (NWAYS == 1) begin : EVICT_ONE
            always_comb begin
                evict_vec = '1;
            end
        end else begin : EVICT_NWAY
            always_comb begin
                node = '0;
                base = '0;
                span = NWAYS[$clog2(NWAYS):0];
                for (integer lvl = 0; lvl < $clog2(NWAYS); lvl++) begin
                    span = span >> 1;
                    if (lru_dout[node] == 1'b0) begin
                        base = base + span;    
                        node = (node << 1) + 2'd2;     // move to right child
                    end else begin
                        node = (node << 1) + 1'b1;     // move to left child
                    end
                end
                evict_vec = '0;
                evict_vec[base] = 1'b1;
            end
        end
    endgenerate

    logic[$clog2(NWAYS):0] node2;
    logic[$clog2(NWAYS):0]  base2;
    logic[$clog2(NWAYS):0] span2;
    generate
        if (NWAYS == 1) begin : LRU_ONE
            always_comb begin
                lru_din = '0;
            end
        end else begin : LRU_NWAY
            always_comb begin
                node2 = '0;
                base2 = '0;
                span2 = NWAYS[$clog2(NWAYS):0];
                lru_din = lru_dout;
                for (integer lvl = 0; lvl < $clog2(NWAYS); lvl++) begin
                    span2 = span2 >> 1;
                    cmp_lhs = {1'b0, hit_way};
                    cmp_rhs = base2 + span2;
                    if (cmp_lhs < cmp_rhs) begin
                        lru_din[node2] = 1'b0;
                        node2 = (node2 << 1) + 1'b1;
                    end else begin
                        lru_din[node2] = 1'b1;
                        node2 = (node2 << 1) + 2'd2;
                        base2 = base2 + span2;
                    end
                end
            end
        end
    endgenerate


    // PLRU Magic - Tree PLRU for 4-way
    // lru_dout = {L2, L1, L0}
    // L0: 0=ways 0,1 more recent than 2,3; 1=ways 2,3 more recent than 0,1
    // L1: 0=way 0 more recent than 1; 1=way 1 more recent than 0  
    // L2: 0=way 2 more recent than 3; 1=way 3 more recent than 2
    // always_comb begin
    //     if (lru_dout[0] == 0) begin
    //         // Ways 0,1 are more recent, so evict from ways 2,3
    //         evict_vec = lru_dout[2] ? 4'b0100 : 4'b1000; // L2=1 -> evict way 2, L2=0 -> evict way 3
    //     end else begin
    //         // Ways 2,3 are more recent, so evict from ways 0,1
    //         evict_vec = lru_dout[1] ? 4'b0001 : 4'b0010; // L1=1 -> evict way 0, L1=0 -> evict way 1
    //     end
    // end  

    // assign evict_way =  evict_vec[3] ? 2'd3 :
    //                     evict_vec[2] ? 2'd2 :
    //                     evict_vec[1] ? 2'd1 :
    //                     evict_vec[0] ? 2'd0 : 2'd0;
    enum logic [2:0] {
        COMPARE,
        MISS_START,
        ALLOCATE,
        WRITEBACK,
        ALLOC_IDLE,
        WRITE_IDLE
    } state, next_state;
    
    logic dirty;
    logic [3:0] mask_d, mask_q;
    logic hazard_d, hazard_q;
    logic [31:0] stored_data_d, stored_data_q;
    logic [31:0] forwarded_data;
    logic flush_waiting;

    always_ff @(posedge clk) begin
        if (rst) begin
            flush_waiting <= 1'b0;
        end else begin
            if (stage_flush && (state == WRITEBACK)) begin
                flush_waiting <= 1'b1;
            end else if(dfp_resp) begin
                flush_waiting <= 1'b0;
            end
        end
    end
    
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= COMPARE;
            hazard_q <= '0;
            stored_data_q <= '0;
            mask_q <= '0;
        end else if ((flush_waiting && dfp_resp) || (stage_flush && dfp_resp) || flush) begin
            state <= COMPARE;
        end else if (s1.valid) begin
            state <= next_state;
        end
        stored_data_q <= stored_data_d;
        hazard_q <= hazard_d;
        mask_q <= mask_d;
    end

    assign busy = (state == WRITEBACK);
    
    // assign stall = (s1.valid && s1.write && hit && (ufp_rmask != 4'b0)) ||
    //                (s1.valid && !hit);

    always_comb begin
        dd_web    = {NWAYS{1'b1}}; // inactive
        tv_web    = {NWAYS{1'b1}};
        for (integer i = 0; i < NWAYS; i++) begin
            wmask[i] = 32'b0;
        end
        data_din = 256'b0;
        tag_din   = {27 - $clog2(NSETS) {1'b0}};
        valid_din = 1'b0;
        dirty_din = 1'b0;
        ufp_resp  = 1'b0;
        ufp_rdata = 32'b0;
        lru_web    = 1'b1;
        next_state = state; 
        data_csb   = {NWAYS{1'b1}}; // inactive
        lru_csb    = 1'b1;
        hazard_d = '0;
        mask_d = '0;
        stored_data_d = '0;
        mask_d = '0;
        array_addr = ufp_addr[4+$clog2(NSETS):5];
        tv_addr = ufp_addr[4+$clog2(NSETS):5];
        lru_addr = s1.index;
        dfp_addr = (next_state == WRITEBACK) ? {tag_dout[evict_way], s1.index, 5'b0} : {s1.tag, s1.index, 5'b0};
        dfp_wdata = data_dout[evict_way];
        dfp_write = (next_state == WRITEBACK && !dfp_resp) ? '1 : '0;
        dfp_read = (next_state == ALLOCATE && !dfp_resp) ? '1 : '0;

        if (state == WRITE_IDLE) begin
            next_state = COMPARE;
            hazard_d = (ufp_addr == {s1.tag, s1.index, s1.offset});
            stored_data_d = s1.data;
            mask_d = s1.mask;
        end
        
        // // Form forwarded data: merge stored write data with cache data based on mask
        // forwarded_data = data_dout[hit_way][32 * s1.offset[4:2] +: 32];
        // for (integer unsigned i = 0; i < 4; i++) begin
        //     if (s1.mask[i]) begin
        //         forwarded_data[i*8 +: 8] = s1.data[i*8 +: 8];
        //     end
        // end
        
        if (!stall && (|ufp_rmask)) begin
            data_csb = '0;  
        end

        if (s1.valid) begin
            if (hit) begin
                next_state = COMPARE;
                if (state == COMPARE) begin                    
                    lru_addr = s1.index;
                    lru_csb = '0;
                    lru_web = '0;
                    // lru_din = (hit_vec[0] ? {lru_dout[2], 1'b0, 1'b0} :     // Way 0: L1=0, L0=0
                    //            hit_vec[1] ? {lru_dout[2], 1'b1, 1'b0} :     // Way 1: L1=1, L0=0
                    //            hit_vec[2] ? {1'b0, lru_dout[1], 1'b1} :     // Way 2: L2=0, L0=1
                    //                         {1'b1, lru_dout[1], 1'b1});     // Way 3: L2=1, L0=1
                end

                if (!s1.write) begin
                    // ufp_rdata = hazard_q ? stored_data_q : data_dout[hit_way][32 * s1.offset[4:2] +: 32];
                    ufp_rdata = data_dout[hit_way][32 * s1.offset[4:2] +: 32];
                     if (hazard_q) begin
                        // lets say there is a RAW to the same address
                        // the write sends the data it wrote
                        // the read reads normally but then overwrites the data it read with the value the write wrote
                        for (integer unsigned i = 0; i < 4; i++) begin
                            if (mask_q[i]) begin
                                ufp_rdata[i*8 +: 8] = stored_data_q[i*8 +: 8];
                            end
                        end
                    end
                    ufp_resp = '1;                
                    end
                else begin
                    if (state == COMPARE) begin
                        next_state = (|ufp_rmask) ? WRITE_IDLE : COMPARE;
                        for (integer i = 0; i < NWAYS; i++) begin 
                            wmask[i] = hit_vec[i] ? ({28'b0, s1.mask} << s1.offset[4:0]) : 32'b0;
                        end
                        data_csb = ~hit_vec;
                        array_addr = s1.index;
                        dd_web = ~hit_vec;
                        data_din = '0;
                        data_din[s1.offset[4:2]*32 +: 32] = s1.data;
                        dirty_din = '1;
                        ufp_resp = '1;                        
                    end
                end
            end
            else begin
                array_addr = s1.index;
                tv_addr = s1.index;
                data_csb = '0;
                lru_addr = s1.index;
                lru_csb = '0;
                case(state) 
                    COMPARE: begin                        
                        next_state = MISS_START;
                    end
                    MISS_START: begin
                        dirty = valid_dout[evict_way] && dirty_dout[evict_way];
                        next_state = dirty ? WRITEBACK : ALLOCATE;                    
                        end
                    WRITEBACK: begin
                        next_state = dfp_resp ? ALLOCATE : WRITEBACK;                    
                        end
                    ALLOCATE: begin
                        next_state = dfp_resp ? ALLOC_IDLE : ALLOCATE;                        
                        if (dfp_resp) begin
                            dd_web = ~evict_vec;
                            tv_web = ~evict_vec;
                            valid_din = '1;
                            dirty_din = '0;
                            tag_din = s1.tag;
                            data_din = dfp_rdata;
                            for (integer j = 0; j < NWAYS; j++) begin
                                wmask[j] = evict_vec[j] ? '1 : 32'b0;
                            end
                        end
                    end
                    ALLOC_IDLE: begin
                        // data_csb = ~evict_vec;
                        next_state = COMPARE;                    
                        end
                    WRITE_IDLE: begin
                        next_state = COMPARE;
                        hazard_d = (ufp_addr == {s1.tag, s1.index, s1.offset} && |ufp_rmask && s1.write);
                        stored_data_d = s1.data;  
                        mask_d = s1.mask;            
                        end
                    default: next_state = state;
                endcase
            end
        end
    end

endmodule