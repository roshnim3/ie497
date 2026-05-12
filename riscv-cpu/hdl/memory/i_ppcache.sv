module i_ppcache 
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
    output  logic   [31:0]  ufp_rdata,
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
    output  logic [31:0]    stage_addr
);
    // wires for modules
    logic [NWAYS-1:0] tv_web, dd_web;  
    logic [31:0]  wmask [NWAYS-1:0];
    logic [$clog2(NSETS)-1:0] array_addr;              
    logic [$clog2(NSETS)-1:0] lru_addr;
    logic [255:0] data_din;          
    logic [255:0] data_dout [NWAYS-1:0];    
    logic [27-$clog2(NSETS)-1:0] tag_din;          
    logic [27-$clog2(NSETS)-1:0] tag_dout [NWAYS-1:0];     
    logic valid_din;           
    logic [NWAYS-1:0] valid_dout;        
    logic [NWAYS-1:0] data_csb, tag_csb;

    logic lru_web;                  
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
            .csb0       (tag_csb[i]),  // always selected
            .web0       (tv_web[i]),
            .addr0      (array_addr),
            .din0       (tag_din),
            .dout0      (tag_dout[i])
        );
        sp_ff_array valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       ('0),  // always selected
            .web0       (tv_web[i]),
            .addr0      (array_addr),
            .din0       (valid_din),
            .dout0      (valid_dout[i])
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
        logic        valid;
    } stage_t;
    
    stage_t s1;
    logic stall;

    assign stage_addr = {s1.tag, s1.index, s1.offset};
    localparam integer IDX_W = (NWAYS > 1) ? $clog2(NWAYS) : 1;
    logic [IDX_W-1:0] hit_way, evict_way;
    logic hit;
    logic [NWAYS-1:0] hit_vec, evict_vec; 

    logic [IDX_W:0] cmp_lhs;
    logic [IDX_W:0] cmp_rhs;

    always_ff @(posedge clk) begin
        if (rst) begin
            s1 <= '0;
        end else if (stage_flush) begin
            s1 <= '0;
        end else if (!stall) begin
            s1.tag <= ufp_addr[31:5+$clog2(NSETS)];
            s1.index <=  ufp_addr[5+$clog2(NSETS)-1:5];
            s1.offset <= ufp_addr[4:0];
            s1.mask <= ufp_rmask;
            s1.valid <= |ufp_rmask;
        end else if(stall && hit) begin
            s1.valid <= 1'b0; 
        end
    end    

    assign stall = s1.valid && (!hit);
    
    assign cache_ready = ~stall;

    
    assign hit = s1.valid && |hit_vec;

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

    always_comb begin
        evict_way = '0;
        for (integer unsigned i = 0; i < NWAYS; i++) begin
            if (evict_vec[i]) begin
                evict_way = (IDX_W)'(i);
            end
        end
    end

    enum logic [1:0] {
        COMPARE,
        ALLOCATE,
        ALLOC_IDLE
    } state, next_state;
    

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= COMPARE;
        end else if (flush) begin
            state <= COMPARE;
        end else if (s1.valid) begin
            state <= next_state;
        end
    end

    always_comb begin
        dd_web    = {NWAYS{1'b1}}; // inactive
        tv_web    = {NWAYS{1'b1}};
        for (integer i = 0; i < NWAYS; i++) begin
            wmask[i] = 32'b0;
        end
        data_din  = 256'b0;
        tag_din   = {27 - $clog2(NSETS) {1'b0}};
        valid_din = 1'b0;
        ufp_resp  = 1'b0;
        ufp_rdata = 32'b0;
        lru_web    = 1'b1;
        next_state = state; 
        data_csb   = {NWAYS{1'b1}}; // inactive
        tag_csb    = {NWAYS{1'b0}};
        lru_csb    = 1'b1;
        array_addr = s1.index;
        lru_addr = s1.index;
        dfp_addr = {s1.tag, s1.index, 5'b0};
        dfp_wdata = '0;
        dfp_write ='0;
        dfp_read = (next_state == ALLOCATE && !dfp_resp) ? '1 : '0;

        if (!stall && (|ufp_rmask)) begin
            data_csb = '0;  
            array_addr = ufp_addr[4+$clog2(NSETS):5];
        end

        if (s1.valid) begin
            if (hit) begin
                if (state == COMPARE) begin                    
                    lru_addr = s1.index;
                    lru_csb = '0;
                    lru_web = '0;
                end
                ufp_rdata = data_dout[hit_way][32 * s1.offset[4:2] +: 32];
                ufp_resp = '1;
            end
            else begin
                lru_addr = s1.index;
                lru_csb = '0;
                case(state) 
                    COMPARE: begin                        
                        next_state = ALLOCATE;
                    end 
                    ALLOCATE: begin
                        next_state = dfp_resp ? ALLOC_IDLE : ALLOCATE;                        
                        if (dfp_resp) begin
                            data_csb = ~evict_vec;
                            array_addr = s1.index;
                            dd_web = ~evict_vec;
                            tv_web = ~evict_vec;
                            valid_din = '1;
                            tag_din = s1.tag;
                            data_din = dfp_rdata;
                            for (integer j = 0; j < NWAYS; j++) begin
                                wmask[j] = evict_vec[j] ? '1 : 32'b0;
                            end
                        end
                    end
                    ALLOC_IDLE: begin
                        next_state = COMPARE;                    
                        end
                    default: next_state = state;
                endcase
            end
        end
    end

endmodule