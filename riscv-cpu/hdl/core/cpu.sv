module cpu
import ooo_types::*;
(
    input   logic               clk,
    input   logic               rst,

    output  logic   [31:0]      bmem_addr,
    output  logic               bmem_read,
    output  logic               bmem_write,
    output  logic   [63:0]      bmem_wdata,
    input   logic               bmem_ready,

    input   logic   [31:0]      bmem_raddr,
    input   logic   [63:0]      bmem_rdata,
    input   logic               bmem_rvalid,

    // Parser write port for the fetch_trade BRAM. Drive these from a
    // behavioral parser model (or the OpenNIC parser hardware) to stream
    // packets into the CPU. Tie to 0 for non-streaming benchmarks.
    input   logic               parser_we,
    input   logic   [2:0]       parser_addr,
    input   logic   [31:0]      parser_data,
    input   logic               parser_commit,

    // TX AXI-Stream master — driven by the pkt_tx FU when firmware issues
    // a pkt_s. Connect to a sink (testbench fake_packet_sink or a CMAC
    // width-converter+adapter on hardware). tready ignored in Phase 1.
    output  logic               m_axis_pkt_tx_tvalid,
    output  logic   [31:0]      m_axis_pkt_tx_tdata,
    output  logic   [3:0]       m_axis_pkt_tx_tkeep,
    output  logic               m_axis_pkt_tx_tlast,
    input   logic               m_axis_pkt_tx_tready
);

    // RVFI packet
    rvfi_packet_t fetch_rvfi_packet;
    rvfi_packet_t decode_rvfi_packet;
    logic [63:0] order;

    // Commit and flush signals
    logic [1:0] commit;
    logic [1:0] flush;

    // RAT, RRAT, and freelist signals
    rat_entry_t     rat_out [31:0];
    logic           alloc_req;
    logic   [1:0]   free_req;
    logic   [5:0]   alloc_reg;
    logic   [1:0][5:0]   free_reg;
    logic           freelist_empty;
    logic           freelist_full;
    logic           rat_wen;
    logic   [4:0]   rat_waddr;
    rat_entry_t     rat_wdata;
    logic   [4:0]   rat_rs1_raddr;
    logic   [4:0]   rat_rs2_raddr;
    rat_entry_t     rat_rs1_rdata;
    rat_entry_t     rat_rs2_rdata;
    rat_entry_t     rrat_out [31:0];

    //rename signals
    rename_packet_t rename_pkt;

    // Decode signals
    decode_packet_t decode_packet;

    // Fetch signals       
    logic [31:0]    inst_in, pc;
    fetch_packet_t  fetch_packet;
    logic           fetch_q_full;

    // Branch predictor signals
    logic           pred_taken;
    logic [31:0]    pred_target;        // BTB target
    logic [31:0]    final_pred_target;  // Final target (BTB or RAS)
    logic [1:0]     pht_counter;
    logic [7:0]     pht_index;   
    logic           bp_ready;
    logic           bp_update_queue_full;
    br_pred_t       branch_predict;
    
    // BP update signals (from CDB via branch execution)
    logic           branch_done;
    logic           branch_outcome;
    logic [7:0]     branch_index;  
    logic [1:0]     branch_counter;
    logic [31:0]    branch_target;
    logic [31:0]    branch_pc;
    logic           branch_mispred;
    
    // RAS signals
    logic           fetch_is_call;               // Early decode in fetch
    logic           fetch_is_return;             // Early decode in fetch
    logic [31:0]    ras_target;
    logic           ras_valid;
    logic [31:0]    fetch_inst;
    logic [31:0]    fetch_pc;                    // PC of instruction from cache

    // Cache signals
    logic           cache_resp;
    logic           i_mem_flush;  // Flush for instruction memory stack 
    logic           d_mem_flush;  // Flush for data memory stack
    logic           d_cache_busy;  // D-cache busy signal (e.g., during writeback)
    
    // Instruction Cache and adapter signals
    logic   [31:0]  i_dfp_addr;
    logic           i_dfp_read, i_dfp_write, i_dfp_resp;
    logic   [255:0] i_dfp_rdata, i_dfp_wdata;
    logic   [31:0]  i_stage_addr;
    logic           i_cache_ready;

    // Data Cache and adapter signals
    logic   [31:0]  d_dfp_addr;
    logic           d_dfp_read, d_dfp_write, d_dfp_resp;
    logic   [255:0] d_dfp_rdata, d_dfp_wdata;
    
    // Data cache UFP signals (connected to mem FU)
    logic   [31:0]  dcache_addr;
    logic   [3:0]   dcache_rmask, dcache_wmask;
    logic   [31:0]  dcache_rdata, dcache_wdata;
    logic           dcache_resp;
    logic           d_cache_ready;

    // Linebuffer signals
    logic   [26:0]  linebuf_tagout, linebuf_tagin;
    logic   [255:0] linebuf_dout, linebuf_din;
    logic           linebuf_wr_en;

    // adapter and arbiter signals
    logic   [31:0]  i_burst_addr, i_arb_addr;
    logic   [63:0]  i_arb_wdata, i_burst_rdata;
    logic           i_arb_read, i_arb_write, i_burst_valid, i_arb_ready, i_req_done;
    
    logic   [31:0]  d_burst_addr, d_arb_addr;
    logic   [63:0]  d_arb_wdata, d_burst_rdata;
    logic           d_arb_read, d_arb_write, d_burst_valid, d_arb_ready, d_req_done;

    // ROB signals
    logic           rob_full, rob_empty;
    rob_entry_t [1:0]     rob_head_entry;
    rob_entry_t     rob_new_entry;
    logic [$clog2(ROB_SIZE) - 1 : 0] rob_index;
    logic [$clog2(ROB_SIZE) - 1 : 0] rob_head_index;

    // Reservation station signals
    logic           rs_br_full, rs_br_empty;
    logic           rs_alu_full, rs_alu_empty;
    logic           rs_mul_full, rs_mul_empty;
    logic           rs_div_full, rs_div_empty;
    logic           rs_mem_full, rs_mem_empty;
    logic           rs_ft_full,  rs_ft_empty;
    logic           rs_pt_full,  rs_pt_empty;

    rs_br_entry_t           rs_br_enq;
    rs_alu_entry_t          rs_alu_enq;
    rs_mul_entry_t          rs_mul_enq;
    rs_div_entry_t          rs_div_enq;
    rs_mem_entry_t          rs_mem_enq;
    rs_fetch_trade_entry_t  rs_ft_enq;
    rs_pkt_tx_entry_t       rs_pt_enq;
    
    // LSQ signals
    logic           lsq_full, lsq_empty;
    logic [$clog2(LSQ_SIZE)-1:0] next_lsq_index;
    
    // LSQ entry signal - converted from rs_mem_enq
    lsq_entry_t     lsq_enq;

    // dispatch and CDB signals
    rs_br_entry_t   rs_br_ready_entry;

    rs_alu_entry_t  rs_alu_ready_entry;

    rs_mul_entry_t  rs_mul_ready_entry;

    rs_div_entry_t  rs_div_ready_entry;

    rs_mem_entry_t  rs_mem_ready_entry;

    rs_fetch_trade_entry_t  rs_ft_ready_entry;

    rs_pkt_tx_entry_t       rs_pt_ready_entry;
    logic [31:0]            pt_pr1_data;
    fu_pkt_tx_pkt           pt_pkt;
    logic                   pkt_tx_busy;

    cdb_br_pkt      cdb_br;
    cdb_alu_pkt     cdb_alu, cdb_alu_latched;
    cdb_alu_br_pkt  cdb_alu_br;
    cdb_mul_div_pkt cdb_mul;
    cdb_mul_div_pkt cdb_div;
    cdb_mul_div_pkt cdb_mul_div;
    cdb_mul_div_pkt cdb_mul_buf_dout;
    logic           cdb_mul_buf_enq, cdb_mul_buf_deq;
    logic           cdb_mul_buf_full, cdb_mul_buf_empty;
    cdb_mul_div_pkt cdb_trade;                  // fetch_trade FU output, shares mul/div lane
    cdb_mul_div_pkt cdb_trade_buf_dout;
    logic           cdb_trade_buf_enq, cdb_trade_buf_deq;
    logic           cdb_trade_buf_full, cdb_trade_buf_empty;
    cdb_mul_div_pkt cdb_pkt_tx;                 // pkt_tx FU output, shares mul/div lane
    cdb_mul_div_pkt cdb_pkt_tx_buf_dout;
    logic           cdb_pkt_tx_buf_enq, cdb_pkt_tx_buf_deq;
    logic           cdb_pkt_tx_buf_full, cdb_pkt_tx_buf_empty;
    cdb_mem_pkt     cdb_mem;

    // Simplified wakeup packets for RS (only valid and rd_paddr)
    cdb_wakeup_pkt  cdb_alu_br_wakeup;
    cdb_wakeup_pkt  cdb_mul_div_wakeup;
    cdb_wakeup_pkt  cdb_mem_wakeup;

    // Simplified RAT packets (valid, rd_paddr, rd_addr)
    cdb_rat_pkt     cdb_alu_br_rat;
    cdb_rat_pkt     cdb_mul_div_rat;
    cdb_rat_pkt     cdb_mem_rat;

    // Simplified ROB packets
    cdb_alu_br_rob_pkt   cdb_alu_br_rob;
    cdb_mul_div_rob_pkt  cdb_mul_div_rob;

    // Simplified ROB commit packet for RRAT and RAT
    rob_commit_pkt [1:0]  rob_commit;

    logic           rs_full;
    logic           alu_rs_stall;  // Stall ALU RS when BR has CDB priority

    // Functional unit Signals
    logic  [31:0]   br_pr1_data, br_pr2_data;
    fu_br_pkt       br_pkt;

    logic  [31:0]   alu_pr1_data, alu_pr2_data;
    fu_alu_pkt      alu_pkt;

    logic [31:0]    mul_pr1_data, mul_pr2_data;
    fu_mul_pkt      mul_pkt;

    logic [31:0]    div_pr1_data, div_pr2_data;
    fu_div_pkt      div_pkt;

    logic [31:0]    mem_pr1_data, mem_pr2_data;
    fu_mem_pkt      mem_pkt;
    logic           fu_mem_ready;

    fu_fetch_trade_pkt ft_pkt;

    // Memory address/data calculation signals
    logic           addr_data_valid;
    logic [31:0]    addr_data_addr;
    logic [31:0]    addr_data_data;

    logic           div_complete;
    
    // Debug: monitor mem_pkt    // Memory flush: only flush memory pipeline when jumping to different cache line
    // I-stack can flush independently, D-stack must wait if cache is busy (e.g., writeback)
    assign i_mem_flush = flush[0] ? (i_stage_addr[31:5] != rob_head_entry[0].branch_target[31:5]) : flush[1] ? (i_stage_addr[31:5] != rob_head_entry[1].branch_target[31:5]) : 1'b0;
    assign d_mem_flush = ((|flush)) && !d_cache_busy;
    // Create simplified wakeup packets for RS (only valid and rd_paddr needed for wakeup)
    assign cdb_alu_br_wakeup.valid = cdb_alu_br.valid;
    assign cdb_alu_br_wakeup.rd_paddr = cdb_alu_br.rd_paddr;
    
    assign cdb_mul_div_wakeup.valid = cdb_mul_div.valid;
    assign cdb_mul_div_wakeup.rd_paddr = cdb_mul_div.rd_paddr;
    
    assign cdb_mem_wakeup.valid = cdb_mem.valid;
    assign cdb_mem_wakeup.rd_paddr = cdb_mem.rd_paddr;

    // Create simplified RAT packets (valid, rd_paddr, rd_addr needed for RAT ready updates)
    assign cdb_alu_br_rat.valid = cdb_alu_br.valid;
    assign cdb_alu_br_rat.rd_paddr = cdb_alu_br.rd_paddr;
    assign cdb_alu_br_rat.rd_addr = cdb_alu_br.rd_addr;
    
    assign cdb_mul_div_rat.valid = cdb_mul_div.valid;
    assign cdb_mul_div_rat.rd_paddr = cdb_mul_div.rd_paddr;
    assign cdb_mul_div_rat.rd_addr = cdb_mul_div.rd_addr;
    
    assign cdb_mem_rat.valid = cdb_mem.valid;
    assign cdb_mem_rat.rd_paddr = cdb_mem.rd_paddr;
    assign cdb_mem_rat.rd_addr = cdb_mem.rd_addr;

    // Create simplified ROB packets (ROB needs different fields than PRF)
    assign cdb_alu_br_rob.valid = cdb_alu_br.valid;
    assign cdb_alu_br_rob.rob_index = cdb_alu_br.rob_index;
    assign cdb_alu_br_rob.result = cdb_alu_br.result;
    assign cdb_alu_br_rob.rs1_val = cdb_alu_br.rs1_val;
    assign cdb_alu_br_rob.rs2_val = cdb_alu_br.rs2_val;
    assign cdb_alu_br_rob.branch_target = cdb_alu_br.branch_target;
    assign cdb_alu_br_rob.br_result = cdb_alu_br.br_result;
    
    assign cdb_mul_div_rob.valid = cdb_mul_div.valid;
    assign cdb_mul_div_rob.rob_index = cdb_mul_div.rob_index;
    assign cdb_mul_div_rob.result = cdb_mul_div.result;
    assign cdb_mul_div_rob.rs1_val = cdb_mul_div.rs1_val;
    assign cdb_mul_div_rob.rs2_val = cdb_mul_div.rs2_val;

    // Create simplified ROB commit packet for RRAT and RAT (only valid, rd_addr, rd_paddr needed)
    assign rob_commit[0].valid = commit[0];
    assign rob_commit[0].rd_addr = rob_head_entry[0].rd_addr;
    assign rob_commit[0].rd_paddr = rob_head_entry[0].rd_paddr;
    assign rob_commit[1].valid = commit[1];
    assign rob_commit[1].rd_addr = rob_head_entry[1].rd_addr;
    assign rob_commit[1].rd_paddr = rob_head_entry[1].rd_paddr;

    // Stall ALU RS when:
    // 1. BR and ALU both finish (BR takes CDB, ALU gets latched)
    // 2. There's already a latched ALU waiting (prevents overwriting/losing the latched value)
    assign alu_rs_stall = (cdb_br.valid && cdb_alu.valid) || cdb_alu_latched.valid;

    // ALU/BR CDB arbiter (BR has priority like DIV, ALU is secondary like MUL)
    always_comb begin
        // Priority to BR unit
        if (cdb_br.valid) begin
            cdb_alu_br.valid         = 1'b1;
            cdb_alu_br.result        = cdb_br.result;
            cdb_alu_br.rob_index     = cdb_br.rob_index;
            cdb_alu_br.rd_paddr      = cdb_br.rd_paddr;
            cdb_alu_br.rd_addr       = cdb_br.rd_addr;
            cdb_alu_br.rs1_val       = cdb_br.rs1_val;
            cdb_alu_br.rs2_val       = cdb_br.rs2_val;
            cdb_alu_br.branch_target = cdb_br.branch_target;
            cdb_alu_br.br_result     = cdb_br.br_result;
        end
        else if (cdb_alu_latched.valid) begin
            cdb_alu_br.valid         = 1'b1;
            cdb_alu_br.result        = cdb_alu_latched.result;
            cdb_alu_br.rob_index     = cdb_alu_latched.rob_index;
            cdb_alu_br.rd_paddr      = cdb_alu_latched.rd_paddr;
            cdb_alu_br.rd_addr       = cdb_alu_latched.rd_addr;
            cdb_alu_br.rs1_val       = cdb_alu_latched.rs1_val;
            cdb_alu_br.rs2_val       = cdb_alu_latched.rs2_val;
            cdb_alu_br.branch_target = '0;
            cdb_alu_br.br_result     = not_taken;
        end
        else if (cdb_alu.valid) begin
            cdb_alu_br.valid         = 1'b1;
            cdb_alu_br.result        = cdb_alu.result;
            cdb_alu_br.rob_index     = cdb_alu.rob_index;
            cdb_alu_br.rd_paddr      = cdb_alu.rd_paddr;
            cdb_alu_br.rd_addr       = cdb_alu.rd_addr;
            cdb_alu_br.rs1_val       = cdb_alu.rs1_val;
            cdb_alu_br.rs2_val       = cdb_alu.rs2_val;
            cdb_alu_br.branch_target = '0;
            cdb_alu_br.br_result     = not_taken;
        end
        else begin
            cdb_alu_br = '0;
        end
    end

    always_ff @(posedge clk) begin
        if(rst)
            cdb_alu_latched <= '0;
        else if(cdb_br.valid && cdb_alu.valid && !cdb_alu_latched.valid) 
            // Only latch a new ALU result if there isn't already one latched
            cdb_alu_latched <= cdb_alu;
        else if(cdb_alu_latched.valid && !cdb_br.valid)
            // Clear the latch after it broadcasts
            cdb_alu_latched <= '0;
    end

    // MUL result buffer to survive cycles where DIV has priority
    assign cdb_mul_buf_enq = cdb_mul.valid && (cdb_div.valid || !cdb_mul_buf_empty);
    assign cdb_mul_buf_deq = !cdb_div.valid && !cdb_mul_buf_empty;

    queue #(
        .DATA_WIDTH($bits(cdb_mul_div_pkt)),
        .QUEUE_SIZE(4)
    ) mul_result_buffer (
        .clk    (clk),
        .rst    (rst),
        .flush  ((|flush)),
        .enq    (cdb_mul_buf_enq && !cdb_mul_buf_full),
        .deq    (cdb_mul_buf_deq),
        .din    (cdb_mul),
        .dout   (cdb_mul_buf_dout),
        .full   (cdb_mul_buf_full),
        .empty  (cdb_mul_buf_empty)
    );

    // fetch_trade buffers behind mul on the same CDB lane. In HFT workload
    // mul/div are idle, so trade never hits the buffer; the queue is here for
    // correctness in mixed workloads.
    assign cdb_trade_buf_enq = cdb_trade.valid &&
                               (cdb_div.valid || !cdb_mul_buf_empty || cdb_mul.valid || !cdb_trade_buf_empty);
    assign cdb_trade_buf_deq = !cdb_div.valid && cdb_mul_buf_empty &&
                               !cdb_mul.valid && !cdb_trade_buf_empty;

    queue #(
        .DATA_WIDTH($bits(cdb_mul_div_pkt)),
        .QUEUE_SIZE(4)
    ) trade_result_buffer (
        .clk    (clk),
        .rst    (rst),
        .flush  ((|flush)),
        .enq    (cdb_trade_buf_enq && !cdb_trade_buf_full),
        .deq    (cdb_trade_buf_deq),
        .din    (cdb_trade),
        .dout   (cdb_trade_buf_dout),
        .full   (cdb_trade_buf_full),
        .empty  (cdb_trade_buf_empty)
    );

    // pkt_tx queues behind trade on the same CDB lane. Same rationale —
    // mul/div idle in HFT workload, but the queue handles the rare collision.
    assign cdb_pkt_tx_buf_enq = cdb_pkt_tx.valid &&
                                (cdb_div.valid || !cdb_mul_buf_empty || cdb_mul.valid ||
                                 !cdb_trade_buf_empty || cdb_trade.valid || !cdb_pkt_tx_buf_empty);
    assign cdb_pkt_tx_buf_deq = !cdb_div.valid && cdb_mul_buf_empty && !cdb_mul.valid &&
                                cdb_trade_buf_empty && !cdb_trade.valid && !cdb_pkt_tx_buf_empty;

    queue #(
        .DATA_WIDTH($bits(cdb_mul_div_pkt)),
        .QUEUE_SIZE(4)
    ) pkt_tx_result_buffer (
        .clk    (clk),
        .rst    (rst),
        .flush  ((|flush)),
        .enq    (cdb_pkt_tx_buf_enq && !cdb_pkt_tx_buf_full),
        .deq    (cdb_pkt_tx_buf_deq),
        .din    (cdb_pkt_tx),
        .dout   (cdb_pkt_tx_buf_dout),
        .full   (cdb_pkt_tx_buf_full),
        .empty  (cdb_pkt_tx_buf_empty)
    );

    // MUL/DIV/TRADE/PKT_TX CDB arbiter — DIV > mul_buf > MUL > trade_buf > TRADE > pkt_tx_buf > PKT_TX
    always_comb begin
        if (cdb_div.valid) begin
            cdb_mul_div = cdb_div;
        end
        else if (!cdb_mul_buf_empty) begin
            cdb_mul_div = cdb_mul_buf_dout;
        end
        else if (cdb_mul.valid) begin
            cdb_mul_div = cdb_mul;
        end
        else if (!cdb_trade_buf_empty) begin
            cdb_mul_div = cdb_trade_buf_dout;
        end
        else if (cdb_trade.valid) begin
            cdb_mul_div = cdb_trade;
        end
        else if (!cdb_pkt_tx_buf_empty) begin
            cdb_mul_div = cdb_pkt_tx_buf_dout;
        end
        else if (cdb_pkt_tx.valid) begin
            cdb_mul_div = cdb_pkt_tx;
        end
        else begin
            cdb_mul_div = '0;
        end
    end

    div div_unit (
        .clk            (clk),
        .rst            (rst),
        .flush          ((|flush)),
        .div_pkt        (div_pkt),
        .div_complete   (div_complete),
        .cdb_div        (cdb_div)
        
    );

    always_comb begin
        if (rs_div_ready_entry.valid & rs_div_ready_entry.rs1_ready & rs_div_ready_entry.rs2_ready) begin
            div_pkt.valid = 1'b1;
            div_pkt.op_a = div_pr1_data;
            div_pkt.op_b = div_pr2_data;
            div_pkt.div_op = rs_div_ready_entry.div_op;
            div_pkt.rd_paddr = rs_div_ready_entry.rd_paddr;
            div_pkt.rd_addr = rs_div_ready_entry.rd_addr;
            div_pkt.rob_index = rs_div_ready_entry.rob_index;
        end
        else begin
            div_pkt = '0;
        end
    end

    mul mul_unit (
        .clk            (clk),
        .rst            (rst),
        .flush          ((|flush)),
        .mul_pkt        (mul_pkt),
        .cdb_mul        (cdb_mul)
    );

    always_comb begin
        if (rs_mul_ready_entry.valid & rs_mul_ready_entry.rs1_ready & rs_mul_ready_entry.rs2_ready) begin
            mul_pkt.valid = 1'b1;
            mul_pkt.op_a = mul_pr1_data;
            mul_pkt.op_b = mul_pr2_data;
            mul_pkt.mul_op = rs_mul_ready_entry.mul_op;
            mul_pkt.rd_paddr = rs_mul_ready_entry.rd_paddr;
            mul_pkt.rd_addr = rs_mul_ready_entry.rd_addr;
            mul_pkt.rob_index = rs_mul_ready_entry.rob_index;
        end
        else begin
            mul_pkt = '0;
        end
    end

    br br_unit (
        .br_pkt     (br_pkt),
        .cdb_br     (cdb_br)
    );

    always_comb begin
        if (rs_br_ready_entry.valid & rs_br_ready_entry.rs1_ready & rs_br_ready_entry.rs2_ready) begin
            br_pkt.valid       = 1'b1;
            br_pkt.op_a        = br_pr1_data;
            br_pkt.op_b        = br_pr2_data;
            br_pkt.cmp_op      = rs_br_ready_entry.cmp_op;
            br_pkt.pc          = rs_br_ready_entry.pc;
            br_pkt.imm         = rs_br_ready_entry.imm;
            br_pkt.rd_paddr    = rs_br_ready_entry.rd_paddr;
            br_pkt.rd_addr     = rs_br_ready_entry.rd_addr;
            br_pkt.pht_counter = rs_br_ready_entry.pht_counter;
            br_pkt.pht_index   = rs_br_ready_entry.pht_index;
            br_pkt.rob_index   = rs_br_ready_entry.rob_index;
        end else begin
            br_pkt = '0;
        end
    end

    alu alu_unit (
        .rs1_val    (alu_pr1_data),
        .rs2_val    (alu_pr2_data),
        .alu_pkt    (alu_pkt),
        .cdb_alu    (cdb_alu)
    );

    fetch_trade fetch_trade_unit (
        .clk           (clk),
        .rst           (rst),
        .flush         ((|flush)),
        .ft_pkt        (ft_pkt),
        .parser_we     (parser_we),
        .parser_addr   (parser_addr),
        .parser_data   (parser_data),
        .parser_commit (parser_commit),
        .cdb_trade     (cdb_trade)
    );

    always_comb begin
        if (rs_ft_ready_entry.valid) begin
            ft_pkt.valid     = 1'b1;
            ft_pkt.field_idx = rs_ft_ready_entry.field_idx;
            ft_pkt.rd_paddr  = rs_ft_ready_entry.rd_paddr;
            ft_pkt.rd_addr   = rs_ft_ready_entry.rd_addr;
            ft_pkt.rob_index = rs_ft_ready_entry.rob_index;
        end else begin
            ft_pkt = '0;
        end
    end

    pkt_tx pkt_tx_unit (
        .clk            (clk),
        .rst            (rst),
        .flush          ((|flush)),
        .pkt            (pt_pkt),
        .pkt_tx_busy    (pkt_tx_busy),
        .m_axis_tvalid  (m_axis_pkt_tx_tvalid),
        .m_axis_tdata   (m_axis_pkt_tx_tdata),
        .m_axis_tkeep   (m_axis_pkt_tx_tkeep),
        .m_axis_tlast   (m_axis_pkt_tx_tlast),
        .m_axis_tready  (m_axis_pkt_tx_tready),
        .cdb_pkt_tx     (cdb_pkt_tx)
    );

    always_comb begin
        if (rs_pt_ready_entry.valid && rs_pt_ready_entry.rs1_ready) begin
            pt_pkt.valid       = 1'b1;
            pt_pkt.data        = pt_pr1_data;
            pt_pkt.word_offset = rs_pt_ready_entry.word_offset;
            pt_pkt.is_send     = rs_pt_ready_entry.is_send;
            pt_pkt.rd_paddr    = rs_pt_ready_entry.rd_paddr;
            pt_pkt.rd_addr     = rs_pt_ready_entry.rd_addr;
            pt_pkt.rob_index   = rs_pt_ready_entry.rob_index;
        end else begin
            pt_pkt = '0;
        end
    end

    always_comb begin
        if (rs_alu_ready_entry.valid & rs_alu_ready_entry.rs1_ready & rs_alu_ready_entry.rs2_ready) begin
            alu_pkt.valid = 1'b1;
            alu_pkt.op_a = rs_alu_ready_entry.alu_op1_sel == rs1_out ? alu_pr1_data : rs_alu_ready_entry.pc;
            alu_pkt.op_b = rs_alu_ready_entry.alu_op2_sel == rs2_out ? alu_pr2_data : rs_alu_ready_entry.imm;
            alu_pkt.alu_op = rs_alu_ready_entry.alu_op;
            alu_pkt.cmp_op = rs_alu_ready_entry.cmp_op;
            alu_pkt.rob_index = rs_alu_ready_entry.rob_index;
            alu_pkt.rd_paddr = rs_alu_ready_entry.rd_paddr;
            alu_pkt.rd_addr = rs_alu_ready_entry.rd_addr;        end
        else begin
            alu_pkt = '0;
        end
    end

    // Convert rs_mem_enq to lsq_entry_t for LSQ
    always_comb begin
        lsq_enq.valid = rs_mem_enq.valid;
        lsq_enq.addr_valid = 1'b0;      // Will be set when addr_data_valid
        lsq_enq.dependency_mask = '0;   // Will be calculated by LSQ
        lsq_enq.addr = '0;              // Will be filled later when addr_data_valid
        lsq_enq.data = '0;              // Will be filled later when addr_data_valid
        lsq_enq.mem_op = rs_mem_enq.mem_op;
        lsq_enq.mem_type = rs_mem_enq.mem_type;
        lsq_enq.rd_paddr = rs_mem_enq.rd_paddr;
        lsq_enq.rd_addr = rs_mem_enq.rd_addr;
        lsq_enq.rob_index = rs_mem_enq.rob_index;
        lsq_enq.rs1_val = '0;  // Will be filled later when addr_data_valid
        lsq_enq.rs2_val = '0;  // Will be filled later when addr_data_valid
    end

    // Memory address/data calculation from RS ready entry
    always_comb begin
        if (rs_mem_ready_entry.valid & rs_mem_ready_entry.rs1_ready & rs_mem_ready_entry.rs2_ready) begin
            addr_data_valid = 1'b1;
            // Calculate address: rs1_val + imm
            addr_data_addr = mem_pr1_data + rs_mem_ready_entry.imm;
            // For stores, data is rs2_val; for loads, data doesn't matter
            addr_data_data = mem_pr2_data;        end else begin
            addr_data_valid = 1'b0;
            addr_data_addr = '0;
            addr_data_data = '0;
        end
    end

    mem mem_unit (
        .clk            (clk),
        .rst            (rst),
        .flush          ((|flush)),
        .mem_pkt_in     (mem_pkt),
        .fu_mem_ready   (fu_mem_ready),
        .cache_ready    (d_cache_ready),
        .cache_addr     (dcache_addr),
        .cache_rmask    (dcache_rmask),
        .cache_wmask    (dcache_wmask),
        .cache_rdata    (dcache_rdata),
        .cache_wdata    (dcache_wdata),
        .cache_resp     (dcache_resp),
        .cdb_mem        (cdb_mem)
    );

    prf phys_reg_file (
        .clk                (clk),
        .rst                (rst),

        .br_ps1_addr        (rs_br_ready_entry.rs1_paddr),
        .br_ps2_addr        (rs_br_ready_entry.rs2_paddr),
        .br_pr1_data        (br_pr1_data),
        .br_pr2_data        (br_pr2_data),

        .alu_ps1_addr       (rs_alu_ready_entry.rs1_paddr),
        .alu_ps2_addr       (rs_alu_ready_entry.rs2_paddr),
        .alu_pr1_data       (alu_pr1_data),
        .alu_pr2_data       (alu_pr2_data),

        .alu_br_pd_addr     (cdb_alu_br.rd_paddr),
        .alu_br_pd_wen      (cdb_alu_br.valid),
        .alu_br_pd_wdata    (cdb_alu_br.result),

        .mul_ps1_addr       (rs_mul_ready_entry.rs1_paddr),
        .mul_ps2_addr       (rs_mul_ready_entry.rs2_paddr),
        .mul_pr1_data       (mul_pr1_data),
        .mul_pr2_data       (mul_pr2_data),

        .div_ps1_addr       (rs_div_ready_entry.rs1_paddr),
        .div_ps2_addr       (rs_div_ready_entry.rs2_paddr),
        .div_pr1_data       (div_pr1_data),
        .div_pr2_data       (div_pr2_data),

        .mul_div_pd_addr    (cdb_mul_div.rd_paddr),
        .mul_div_pd_wen     (cdb_mul_div.valid),
        .mul_div_pd_wdata   (cdb_mul_div.result),

        .mem_ps1_addr       (rs_mem_ready_entry.rs1_paddr),
        .mem_ps2_addr       (rs_mem_ready_entry.rs2_paddr),
        .mem_pr1_data       (mem_pr1_data),
        .mem_pr2_data       (mem_pr2_data),

        .mem_pd_addr        (cdb_mem.rd_paddr),
        .mem_pd_wen         (cdb_mem.valid),
        .mem_pd_wdata       (cdb_mem.result),

        .pt_ps1_addr        (rs_pt_ready_entry.rs1_paddr),
        .pt_pr1_data        (pt_pr1_data)
    );

       // Reservation Stations
    alu_rs #(
        .RS_SIZE       (ALU_RS_SIZE)
    )
    alu_res_station (
        .clk                (clk),
        .rst                (rst),
        .flush              ((|flush)),
        .stall              (alu_rs_stall),
        .cdb_alu_br_wakeup  (cdb_alu_br_wakeup),
        .cdb_mul_div_wakeup (cdb_mul_div_wakeup),
        .cdb_mem_wakeup     (cdb_mem_wakeup),
        .new_entry          (rs_alu_enq),

        .rs_full            (rs_alu_full),
        .rs_empty           (rs_alu_empty),
        .rs_ready_entry     (rs_alu_ready_entry)
    );

    mul_rs #(
        .RS_SIZE       (MUL_RS_SIZE)
    )
    mul_res_station (
        .clk                (clk),
        .rst                (rst),
        .flush              ((|flush)),
        .cdb_alu_br_wakeup  (cdb_alu_br_wakeup),
        .cdb_mul_div_wakeup (cdb_mul_div_wakeup),
        .cdb_mem_wakeup     (cdb_mem_wakeup),
        .new_entry          (rs_mul_enq),

        .rs_full            (rs_mul_full),
        .rs_empty           (rs_mul_empty),
        .rs_ready_entry     (rs_mul_ready_entry)
    );

    div_rs #(
        .RS_SIZE       (DIV_RS_SIZE)
    )
    div_res_station (
        .clk                (clk),
        .rst                (rst),
        .flush              ((|flush)),
        .cdb_alu_br_wakeup  (cdb_alu_br_wakeup),
        .cdb_mul_div_wakeup (cdb_mul_div_wakeup),
        .cdb_mem_wakeup     (cdb_mem_wakeup),
        .new_entry          (rs_div_enq),
        .div_complete       (div_complete),

        .rs_full            (rs_div_full),
        .rs_empty           (rs_div_empty),
        .rs_ready_entry     (rs_div_ready_entry)
    );

    br_rs #(
        .RS_SIZE       (BR_RS_SIZE)
    )
    br_res_station (
        .clk                (clk),
        .rst                (rst),
        .flush              ((|flush)),
        .cdb_alu_br_wakeup  (cdb_alu_br_wakeup),
        .cdb_mul_div_wakeup (cdb_mul_div_wakeup),
        .cdb_mem_wakeup     (cdb_mem_wakeup),
        .new_entry          (rs_br_enq),

        .rs_full            (rs_br_full),
        .rs_empty           (rs_br_empty),
        .rs_ready_entry     (rs_br_ready_entry)
    );

    lsq #(
        .LSQ_SIZE      (LSQ_SIZE)
    )
    load_store_queue (
        .clk                (clk),
        .rst                (rst),
        .flush              ((|flush)),

        .enq_entry          (lsq_enq),

        .addr_data_valid    (addr_data_valid),
        .addr_data_lsq_index(rs_mem_ready_entry.lsq_index),
        .addr_data_addr     (addr_data_addr),
        .addr_data_data     (addr_data_data),
        .addr_data_rs1_val  (mem_pr1_data),
        .addr_data_rs2_val  (mem_pr2_data),

        .rob_head_idx       (rob_head_index),

        .fu_mem_out         (mem_pkt),
        .fu_mem_ready       (fu_mem_ready),
        .cache_ready        (d_cache_ready),

        .full               (lsq_full),
        .empty              (lsq_empty),
        .next_lsq_index     (next_lsq_index)
    );

    mem_rs #(
        .RS_SIZE       (MEM_RS_SIZE)
    )
    mem_res_station (
        .clk                (clk),
        .rst                (rst),
        .flush              ((|flush)),
        .cdb_alu_br_wakeup  (cdb_alu_br_wakeup),
        .cdb_mul_div_wakeup (cdb_mul_div_wakeup),
        .cdb_mem_wakeup     (cdb_mem_wakeup),
        .new_entry          (rs_mem_enq),

        .rs_full            (rs_mem_full),
        .rs_empty           (rs_mem_empty),
        .rs_ready_entry     (rs_mem_ready_entry)
    );

    fetch_trade_rs #(
        .RS_SIZE       (FT_RS_SIZE)
    )
    fetch_trade_res_station (
        .clk            (clk),
        .rst            (rst),
        .flush          ((|flush)),
        .new_entry      (rs_ft_enq),

        .rs_full        (rs_ft_full),
        .rs_empty       (rs_ft_empty),
        .rs_ready_entry (rs_ft_ready_entry)
    );

    pkt_tx_rs #(
        .RS_SIZE       (PT_RS_SIZE)
    )
    pkt_tx_res_station (
        .clk                (clk),
        .rst                (rst),
        .flush              ((|flush)),
        .stall              (pkt_tx_busy),
        .new_entry          (rs_pt_enq),
        .cdb_alu_br_wakeup  (cdb_alu_br_wakeup),
        .cdb_mul_div_wakeup (cdb_mul_div_wakeup),
        .cdb_mem_wakeup     (cdb_mem_wakeup),

        .rs_full            (rs_pt_full),
        .rs_empty           (rs_pt_empty),
        .rs_ready_entry     (rs_pt_ready_entry)
    );

    // Combine RS and LSQ full signals for memory operations
    // Memory operations need space in BOTH the reservation station AND the LSQ
    logic rs_mem_or_lsq_full;
    assign rs_mem_or_lsq_full = rs_mem_full | lsq_full;
    
    dispatch dispatch_stage (
        .flush                  (|flush),
        .rob_full               (rob_full),
        .rename_pkt             (rename_pkt),

        .cdb_alu_br_wakeup      (cdb_alu_br_wakeup),
        .cdb_mul_div_wakeup     (cdb_mul_div_wakeup),
        .cdb_mem_wakeup         (cdb_mem_wakeup),

        // RS full inputs
        .rs_br_full             (rs_br_full),
        .rs_alu_full            (rs_alu_full),
        .rs_mul_full            (rs_mul_full),
        .rs_div_full            (rs_div_full),
        .rs_mem_full            (rs_mem_or_lsq_full),  // Combined RS+LSQ full signal
        .rs_ft_full             (rs_ft_full),
        .rs_pt_full             (rs_pt_full),

        // LSQ index for mem operations
        .next_lsq_index         (next_lsq_index),

        // RS enqueue outputs
        .rs_br_enq              (rs_br_enq),
        .rs_alu_enq             (rs_alu_enq),
        .rs_mul_enq             (rs_mul_enq),
        .rs_div_enq             (rs_div_enq),
        .rs_mem_enq             (rs_mem_enq),
        .rs_ft_enq              (rs_ft_enq),
        .rs_pt_enq              (rs_pt_enq),

        .rs_full                (rs_full)
    );

 
    rob re_order_buffer (
        .clk                (clk),
        .rst                (rst),
        .flush              (flush), 
        .new_entry          (rob_new_entry),
        .cdb_alu_br_rob     (cdb_alu_br_rob),
        .cdb_mul_div_rob    (cdb_mul_div_rob),
        .cdb_mem            (cdb_mem),
        .bp_update_queue_full (bp_update_queue_full),

        .full               (rob_full),
        .empty              (rob_empty),
        .commit             (commit),
        .head_entry         (rob_head_entry),
        .rob_index          (rob_index),
        .head_index         (rob_head_index)
    );

    freelist freelist (
        .clk            (clk),
        .rst            (rst),
        .flush          ((|flush)), 
        .rob_commit     (rob_commit),
        .alloc_req      (alloc_req),
        .free_req       (free_req), 
        .free_reg       (free_reg), 
        .rrat           (rrat_out), 

        .alloc_reg      (alloc_reg),
        .full           (freelist_full),
        .empty          (freelist_empty)
    );

    rrat rrat (
        .clk            (clk),
        .rst            (rst),
        .commit         (commit), 
        .rob_commit     (rob_commit),

        .rrat_out       (rrat_out),
        .free_reg       (free_reg),
        .free_req       (free_req)
    );

    rat rat(
        .clk                (clk),
        .rst                (rst),
        .flush              ((|flush)),
        .commit             (commit),
        .rob_commit         (rob_commit),
        .rrat_out           (rrat_out), 
        .rat_rs1_raddr      (rat_rs1_raddr),
        .rat_rs2_raddr      (rat_rs2_raddr),
        .rat_wen            (rat_wen),
        .rat_waddr          (rat_waddr),
        .rat_wdata          (rat_wdata),
        .cdb_alu_br_rat     (cdb_alu_br_rat),
        .cdb_mul_div_rat    (cdb_mul_div_rat),
        .cdb_mem_rat        (cdb_mem_rat),

        .rat_rs1_rdata      (rat_rs1_rdata),
        .rat_rs2_rdata      (rat_rs2_rdata),
        .rat_out            (rat_out)
    );

    rename rename_stage (
        .flush              (|flush),
        .alloc_reg          (alloc_reg),
        .freelist_empty     (freelist_empty),
        .rs_full            (rs_full),
        .rob_full           (rob_full),
        .decode_pkt         (decode_packet),
        .decode_rvfi_pkt    (decode_rvfi_packet),
        .rat_rs1_rdata      (rat_rs1_rdata),
        .rat_rs2_rdata      (rat_rs2_rdata),
        .rob_index          (rob_index),

        .alloc_req          (alloc_req),
        .rat_rs1_raddr      (rat_rs1_raddr),
        .rat_rs2_raddr      (rat_rs2_raddr),
        .rat_wen            (rat_wen),
        .rat_waddr          (rat_waddr),
        .rat_wdata          (rat_wdata),

        .rename_pkt         (rename_pkt),
        .rob_entry          (rob_new_entry)
    );

    decode decode_stage (
        .clk                (clk),
        .rst                (rst),
        .flush              (|flush),
        .freelist_empty     (freelist_empty),
        .rs_full            (rs_full),
        .rob_full           (rob_full),
        .fetch_packet       (fetch_packet),

        .decode_packet      (decode_packet),

        .fetch_rvfi_packet  (fetch_rvfi_packet),
        .decode_rvfi_packet (decode_rvfi_packet)
    );

    // Early decode for RAS: detect call and return in fetch stage
    // Call: JAL/JALR with rd != x0 (saves return address)
    // Return: JALR with rd == x0 (doesn't save return address)
    instr_t fetch_inst_decoded;
    logic fetch_is_call_raw, fetch_is_return_raw;
    
    assign fetch_inst_decoded.word = fetch_inst;
    assign fetch_is_call_raw = ((fetch_inst_decoded.r_type.opcode == op_jal && fetch_inst_decoded.j_type.rd != 5'd0) ||
                                (fetch_inst_decoded.r_type.opcode == op_jalr && fetch_inst_decoded.i_type.rd != 5'd0));
    assign fetch_is_return_raw = (fetch_inst_decoded.r_type.opcode == op_jalr) && 
                                 (fetch_inst_decoded.i_type.rd == 5'd0);
    
    assign fetch_is_call = fetch_is_call_raw && fetch_packet.fields.valid;
    assign fetch_is_return = fetch_is_return_raw && fetch_packet.fields.valid;
    
    // Branch predictor instance
    bp #(
        .GHR_BITS (10),
        .PHT_BITS (8),
        .PHT_INIT (2'b01) // Weakly-taken (biased toward taken for loops)
    ) branch_predictor (
        .clk                (clk),
        .rst                (rst),
        .if_pc              (pc),
        .pred_taken         (pred_taken),
        .pht_counter        (pht_counter),
        .pht_index          (pht_index),
        .branch_done        (branch_done),
        .branch_outcome     (branch_outcome),
        .branch_index       (branch_index),
        .branch_counter     (branch_counter),
        .bp_ready           (bp_ready),
        .update_queue_full  (bp_update_queue_full)
    );
        
    // Return Address Stack instance
    // Uses early decode signals for speculative push/pop in fetch stage
    ras #(
        .RAS_SIZE(16)
    ) return_stack (
        .clk            (clk),
        .rst            (rst),
        .is_call        (fetch_is_call),
        .is_return      (fetch_is_return),
        .decode_pc      (fetch_pc), 
        .br_mispredict  (|flush),  
        .ras_target     (ras_target),
        .ras_valid      (ras_valid)
    );
    
    // RAS target is now passed directly to fetch for redirect-on-detection
    // No longer need to select target here - fetch will redirect when it detects a return
    
    // Convert BP prediction to br_pred_t and prepare target
    assign branch_predict = pred_taken ? taken : not_taken;
    assign branch_target = 32'd0;  // TODO: Replace with BTB target when BTB is integrated
    
    // Connect branch update signals from CDB
    // Only update BP for conditional branches (not JAL/JALR)
    assign branch_done    = cdb_br.valid && cdb_br.is_conditional && !bp_update_queue_full;
    assign branch_outcome = (cdb_br.br_result == taken);
    assign branch_index   = cdb_br.pht_index;
    assign branch_counter = cdb_br.pht_counter;

    fetch fetch_stage (
        .clk                (clk),
        .rst                (rst),
        .order              (order),
        .flush              (flush),
        .flush_pc           ({rob_head_entry[1].rvfi_pkt.pc_wdata, rob_head_entry[0].rvfi_pkt.pc_wdata}),
        .inst_in            (inst_in),
        .rob_full           (rob_full),
        .freelist_empty     (freelist_empty),
        .rs_full            (rs_full),
        .cache_resp         (cache_resp),
        .cache_ready        (i_cache_ready),
        .branch_predict     (branch_predict),
        .pht_counter        (pht_counter),
        .pht_index          (pht_index),
        .branch_target      (branch_target),
        .ras_target         (ras_target),
        .ras_valid          (ras_valid),

        .pc                 (pc),
        .fetch_inst_out     (fetch_inst),
        .fetch_pc_out       (fetch_pc),
        .fetch_q_full       (fetch_q_full),
        .fetch_packet       (fetch_packet),

        .fetch_rvfi_packet  (fetch_rvfi_packet)
    );

    always_ff @( posedge clk ) begin
        if (rst) begin
            order <= '0;
        end else if ((|flush)) begin
            order <= flush[0] ? rob_head_entry[0].rvfi_pkt.order + 1 : rob_head_entry[1].rvfi_pkt.order + 1;
        end else if ((!freelist_empty & !rob_full & !rs_full) && fetch_packet.fields.valid) begin
            order <= order + 1;
        end
    end

    // Linebuffer instance (moved from cache to fetch stage for flush control)
    // linebuf line_buffer (
    //     .clk        (clk),
    //     .rst        (rst | (|flush)),
    //     .tagin      (linebuf_tagin),
    //     .din        (linebuf_din),
    //     .wr_en      (linebuf_wr_en),
    //     .tagout     (linebuf_tagout),
    //     .dout       (linebuf_dout)
    // );

    // i_cache i_cache (
    //     .clk            (clk),
    //     .rst            (rst),
    //     .flush          (i_mem_flush),
    //     .ufp_addr       (pc),
    //     .ufp_rmask      (4'b1111 & {4{~(|flush)}}),  // Disable reads during flush
    //     .ufp_wmask      ('0),
    //     .ufp_rdata      (inst_in),
    //     .ufp_wdata      ('0),
    //     .ufp_resp       (cache_resp),
        

    //     .dfp_addr       (i_dfp_addr),
    //     .dfp_read       (i_dfp_read),
    //     .dfp_write      (i_dfp_write),
    //     .dfp_wdata      (i_dfp_wdata),
    //     .dfp_rdata      (i_dfp_rdata),
    //     .dfp_resp       (i_dfp_resp),

    //     .linebuf_tagout (linebuf_tagout),
    //     .linebuf_dout   (linebuf_dout),
    //     .linebuf_tagin  (linebuf_tagin),
    //     .linebuf_din    (linebuf_din),
    //     .linebuf_wr_en  (linebuf_wr_en)
    // );

    i_ppcache i_cache (
        .clk            (clk),
        .rst            (rst),
        .flush          (i_mem_flush),
        .stage_flush    (i_mem_flush),
        .stage_addr     (i_stage_addr),

        .ufp_addr       (pc),
        .ufp_rmask      (4'b1111 & {4{~(|i_mem_flush)}} & {4{~fetch_q_full}} & {4{i_cache_ready}}),  // Disable reads during flush
        .ufp_rdata      (inst_in),
        .ufp_resp       (cache_resp),

        .dfp_addr       (i_dfp_addr),
        .dfp_read       (i_dfp_read),
        .dfp_write      (i_dfp_write),
        .dfp_wdata      (i_dfp_wdata),
        .dfp_rdata      (i_dfp_rdata),
        .dfp_resp       (i_dfp_resp),

        .cache_ready    (i_cache_ready)
    );

    d_ppcache d_cache (
        .clk            (clk),
        .rst            (rst),
        .flush          (d_mem_flush),
        .stage_flush    (|flush),
        .busy           (d_cache_busy),

        .ufp_addr       (dcache_addr),
        .ufp_rmask      (dcache_rmask),
        .ufp_wmask      (dcache_wmask),
        .ufp_rdata      (dcache_rdata),
        .ufp_wdata      (dcache_wdata),
        .ufp_resp       (dcache_resp),
        .cache_ready    (d_cache_ready),

        .dfp_addr       (d_dfp_addr),
        .dfp_read       (d_dfp_read),
        .dfp_write      (d_dfp_write),
        .dfp_wdata      (d_dfp_wdata),
        .dfp_rdata      (d_dfp_rdata),
        .dfp_resp       (d_dfp_resp)
    );


    // d_cache d_cache (
    //     .clk            (clk),
    //     .rst            (rst),
    //     .flush          (d_mem_flush),
    //     .busy           (d_cache_busy),

    //     .ufp_addr       (dcache_addr),
    //     .ufp_rmask      (dcache_rmask),
    //     .ufp_wmask      (dcache_wmask),
    //     .ufp_rdata      (dcache_rdata),
    //     .ufp_wdata      (dcache_wdata),
    //     .ufp_resp       (dcache_resp),

    //     .dfp_addr       (d_dfp_addr),
    //     .dfp_read       (d_dfp_read),
    //     .dfp_write      (d_dfp_write),
    //     .dfp_wdata      (d_dfp_wdata),
    //     .dfp_rdata      (d_dfp_rdata),
    //     .dfp_resp       (d_dfp_resp)
    // );

    adapter #(
        .IS_ICACHE(1)
    ) i_adapter (
        .clk            (clk),
        .rst            (rst),
        .flush          (i_mem_flush),

        .cache_addr     (i_dfp_addr),
        .cache_read     (i_dfp_read),
        .cache_write    (i_dfp_write),
        .cache_wdata    (i_dfp_wdata),
        .cache_rdata    (i_dfp_rdata),
        .cache_resp     (i_dfp_resp),

        .burst_addr     (i_burst_addr),
        .burst_valid    (i_burst_valid),
        .burst_rdata    (i_burst_rdata),

        .arb_addr       (i_arb_addr),
        .arb_read       (i_arb_read),
        .arb_write      (i_arb_write),
        .arb_wdata      (i_arb_wdata),
        .req_done       (i_req_done),
        .arb_ready      (i_arb_ready)
    );

    adapter #(
        .IS_ICACHE(0)
    ) d_adapter (
        .clk            (clk),
        .rst            (rst),
        .flush          (d_mem_flush),

        .cache_addr     (d_dfp_addr),
        .cache_read     (d_dfp_read),
        .cache_write    (d_dfp_write),
        .cache_wdata    (d_dfp_wdata),
        .cache_rdata    (d_dfp_rdata),
        .cache_resp     (d_dfp_resp),

        .burst_addr     (d_burst_addr),
        .burst_valid    (d_burst_valid),
        .burst_rdata    (d_burst_rdata),

        .arb_addr       (d_arb_addr),
        .arb_read       (d_arb_read),
        .arb_write      (d_arb_write),
        .arb_wdata      (d_arb_wdata),
        .req_done       (d_req_done),
        .arb_ready      (d_arb_ready)
    );

    arbiter arbiter (
        .clk        (clk),
        .rst        (rst),
        .d_mem_flush (d_mem_flush),
        .i_mem_flush (i_mem_flush),

        // Instruction adapter connections
        .i_req_addr (i_arb_addr),
        .i_req_read (i_arb_read),
        .i_req_write(i_arb_write),
        .i_req_data (i_arb_wdata),
        .i_burst_data (i_burst_rdata),
        .i_burst_valid(i_burst_valid),
        .i_burst_addr (i_burst_addr),
        .i_req_done   (i_req_done),
        .i_arb_ready  (i_arb_ready),

        // Data adapter connections
        .d_req_addr (d_arb_addr),
        .d_req_read (d_arb_read),
        .d_req_write(d_arb_write),
        .d_req_data (d_arb_wdata),
        .d_burst_data (d_burst_rdata),  
        .d_burst_valid(d_burst_valid),
        .d_burst_addr (d_burst_addr),
        .d_req_done   (d_req_done),
        .d_arb_ready  (d_arb_ready),  

        // BMEM interface
        .bmem_addr  (bmem_addr),
        .bmem_read  (bmem_read),
        .bmem_write (bmem_write),
        .bmem_wdata (bmem_wdata),
        .bmem_ready (bmem_ready),
        .bmem_raddr (bmem_raddr),
        .bmem_rdata (bmem_rdata),
        .bmem_rvalid(bmem_rvalid)
    );

    // RVFI signal
    // logic [1:0] rvfi_valid;
    // logic [1:0][63:0] rvfi_order;
    // logic [1:0][31:0] rvfi_inst;
    // logic [1:0][4:0] rvfi_rs1_addr;
    // logic [1:0][4:0] rvfi_rs2_addr;
    // logic [1:0][31:0] rvfi_rs1_rdata;
    // logic [1:0][31:0] rvfi_rs2_rdata;
    // logic [1:0][4:0] rvfi_rd_addr;
    // logic [1:0][31:0] rvfi_rd_wdata;
    // logic [1:0][31:0] rvfi_pc_rdata;
    // logic [1:0][31:0] rvfi_pc_wdata;
    // logic [1:0][31:0] rvfi_mem_addr;
    // logic [1:0][3:0]  rvfi_mem_rmask;
    // logic [1:0][3:0]  rvfi_mem_wmask;
    // logic [1:0][31:0] rvfi_mem_rdata;
    // logic [1:0][31:0] rvfi_mem_wdata;

    // assign rvfi_valid      = {rob_head_entry[1].rvfi_pkt.valid && commit[1],      rob_head_entry[0].rvfi_pkt.valid && commit[0]};
    // assign rvfi_order      = {rob_head_entry[1].rvfi_pkt.order,      rob_head_entry[0].rvfi_pkt.order};
    // assign rvfi_inst       = {rob_head_entry[1].rvfi_pkt.inst,       rob_head_entry[0].rvfi_pkt.inst};
    // assign rvfi_rs1_addr   = {rob_head_entry[1].rvfi_pkt.rs1_addr,   rob_head_entry[0].rvfi_pkt.rs1_addr};  
    // assign rvfi_rs2_addr   = {rob_head_entry[1].rvfi_pkt.rs2_addr,   rob_head_entry[0].rvfi_pkt.rs2_addr};
    // assign rvfi_rs1_rdata  = {rob_head_entry[1].rvfi_pkt.rs1_rdata,  rob_head_entry[0].rvfi_pkt.rs1_rdata};
    // assign rvfi_rs2_rdata  = {rob_head_entry[1].rvfi_pkt.rs2_rdata,  rob_head_entry[0].rvfi_pkt.rs2_rdata};
    // assign rvfi_rd_addr    = {rob_head_entry[1].rvfi_pkt.rd_addr,    rob_head_entry[0].rvfi_pkt.rd_addr};
    // assign rvfi_rd_wdata   = {rob_head_entry[1].rvfi_pkt.rd_wdata,   rob_head_entry[0].rvfi_pkt.rd_wdata};
    // assign rvfi_pc_rdata   = {rob_head_entry[1].rvfi_pkt.pc_rdata,  rob_head_entry[0].rvfi_pkt.pc_rdata};
    // assign rvfi_pc_wdata   = {rob_head_entry[1].rvfi_pkt.pc_wdata,  rob_head_entry[0].rvfi_pkt.pc_wdata};
    // assign rvfi_mem_addr   = {rob_head_entry[1].rvfi_pkt.mem_addr,   rob_head_entry[0].rvfi_pkt.mem_addr};
    // assign rvfi_mem_rmask  = {rob_head_entry[1].rvfi_pkt.mem_rmask,  rob_head_entry[0].rvfi_pkt.mem_rmask};
    // assign rvfi_mem_wmask  = {rob_head_entry[1].rvfi_pkt.mem_wmask,  rob_head_entry[0].rvfi_pkt.mem_wmask};
    // assign rvfi_mem_rdata  = {rob_head_entry[1].rvfi_pkt.mem_rdata,  rob_head_entry[0].rvfi_pkt.mem_rdata};
    // assign rvfi_mem_wdata  = {rob_head_entry[1].rvfi_pkt.mem_wdata,  rob_head_entry[0].rvfi_pkt.mem_wdata};
endmodule : cpu
 
