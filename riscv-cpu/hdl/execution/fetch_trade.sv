// fetch_trade FU — custom-1 instruction backend with FIFO of parsed packets.
//
// BRAM is organized as 8 packets x 8 slots/packet (64 entries x 32 bits, one
// BRAM18). Within a packet, slots map to fields:
//   0: msg_type   1: side       2: stock_locate   3: seq number
//   4: empty flag (special — returned via combinational mux, not BRAM)
//   5: pop trigger (special — returns "pop succeeded"; advances tail)
//   6: shares     7: price
//
// FIFO discipline: parser writes one packet's fields then pulses
// parser_commit to advance the FU's head_ptr. CPU reads fields from the
// tail packet and issues `fetch_trade _, 5` to advance tail_ptr.
//
// Backward compatibility with static benchmarks (no parser writes): the
// MEMORY_INIT_PARAM populates packet 0 at reset, and head_ptr resets to 1.
// So one packet is always "available" with the init values, and reads to
// slots 0-7 behave exactly like the pre-FIFO design as long as the firmware
// doesn't pop.

module fetch_trade
import ooo_types::*;
(
    input  logic              clk,
    input  logic              rst,
    input  logic              flush,
    input  fu_fetch_trade_pkt ft_pkt,

    // Parser write side (Port A of the parsed-fields BRAM). parser_addr is
    // the field index (0-7) within the current head packet; the FU prepends
    // head_ptr to form the full BRAM address. parser_commit pulses for one
    // cycle when a packet's last field has been written, advancing head.
    input  logic              parser_we,
    input  logic [2:0]        parser_addr,
    input  logic [31:0]       parser_data,
    input  logic              parser_commit,

    output cdb_mul_div_pkt    cdb_trade
);

    localparam int DEPTH      = 8;   // packet slots in the FIFO
    localparam int DEPTH_BITS = 3;   // $clog2(DEPTH)

    // 4-bit pointers: top bit distinguishes wrap, low 3 bits index packet.
    logic [DEPTH_BITS:0] head_ptr;
    logic [DEPTH_BITS:0] tail_ptr;

    logic fifo_empty;
    logic fifo_full;
    assign fifo_empty = (head_ptr == tail_ptr);
    assign fifo_full  = (head_ptr[DEPTH_BITS] != tail_ptr[DEPTH_BITS]) &&
                        (head_ptr[DEPTH_BITS-1:0] == tail_ptr[DEPTH_BITS-1:0]);

    // BRAM addresses: {packet_idx, field_idx}
    logic [5:0] write_addr;
    logic [5:0] read_addr;
    assign write_addr = {head_ptr[DEPTH_BITS-1:0], parser_addr};
    assign read_addr  = {tail_ptr[DEPTH_BITS-1:0], ft_pkt.field_idx};

    logic [31:0]       bram_dout;
    fu_fetch_trade_pkt ft_pipe;
    logic              empty_pipe;   // empty snapshot at the cycle the read fired

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A           (6),
        .ADDR_WIDTH_B           (6),
        .AUTO_SLEEP_TIME        (0),
        .BYTE_WRITE_WIDTH_A     (32),
        .CASCADE_HEIGHT         (0),
        .CLOCKING_MODE          ("common_clock"),
        .ECC_MODE               ("no_ecc"),
        .MEMORY_INIT_FILE       ("none"),
        // 8 values populate packet 0 (BRAM addrs 0-7). Remaining 56 entries
        // (packets 1-7) default to 0. Static benchmarks consume packet 0
        // by reading slots 0-7 without popping, so head=1 keeps it visible.
        //   0:msg_type=0x41  1:side='B' (0x42)  2:stock_locate=0x1234
        //   3:seq=1          4:reserved         5:reserved
        //   6:shares=1000    7:price=100000
        .MEMORY_INIT_PARAM      ("00000041,00000042,00001234,00000001,00000000,00000000,000003E8,000186A0"),
        .MEMORY_OPTIMIZATION    ("true"),
        .MEMORY_PRIMITIVE       ("block"),
        .MEMORY_SIZE            (2048),      // 64 entries x 32 bits
        .MESSAGE_CONTROL        (0),
        .READ_DATA_WIDTH_B      (32),
        .READ_LATENCY_B         (1),
        .READ_RESET_VALUE_B     ("0"),
        .RST_MODE_A             ("SYNC"),
        .RST_MODE_B             ("SYNC"),
        .SIM_ASSERT_CHK         (0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT           (1),
        .USE_MEM_INIT_MMI       (0),
        .WAKEUP_TIME            ("disable_sleep"),
        .WRITE_DATA_WIDTH_A     (32),
        .WRITE_MODE_B           ("read_first"),
        .WRITE_PROTECT          (1)
    ) trade_bram_inst (
        .sleep                  (1'b0),
        .clka                   (clk),
        .ena                    (parser_we),
        .wea                    (parser_we),
        .addra                  (write_addr),
        .dina                   (parser_data),
        .injectsbiterra         (1'b0),
        .injectdbiterra         (1'b0),
        .clkb                   (clk),
        .rstb                   (rst),
        .enb                    (1'b1),
        .regceb                 (1'b1),
        .addrb                  (read_addr),
        .doutb                  (bram_dout),
        .sbiterrb               (),
        .dbiterrb               ()
    );

    // FIFO pointers + pipeline register, all aligned to the BRAM read.
    // Pop fires at issue time (when field_idx==5 with a valid packet). This
    // is a side effect at issue rather than at commit; the firmware in
    // itch_stream.c keeps the polling+read+pop sequence on a straight-line
    // path so speculative squash is not a concern in practice.
    logic do_pop;
    assign do_pop = ft_pkt.valid && (ft_pkt.field_idx == 3'd5) && !fifo_empty;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            head_ptr   <= {1'b0, 3'd1};   // packet 0 pre-init for static benchmarks
            tail_ptr   <= '0;
            ft_pipe    <= '0;
            empty_pipe <= 1'b0;
        end else begin
            ft_pipe    <= ft_pkt;
            empty_pipe <= fifo_empty;

            if (parser_commit && !fifo_full) head_ptr <= head_ptr + 1'b1;
            if (do_pop)                      tail_ptr <= tail_ptr + 1'b1;
        end
    end

    // Result mux. Special slots 4 and 5 bypass BRAM:
    //   slot 4 -> empty flag (1 if FIFO empty)
    //   slot 5 -> {31'b0, !empty} so firmware can check "did the pop work?"
    // All other slots return whatever the BRAM produced for {tail_idx, slot}.
    logic [31:0] result;
    always_comb begin
        case (ft_pipe.field_idx)
            3'd4:    result = {31'b0,  empty_pipe};
            3'd5:    result = {31'b0, ~empty_pipe};
            default: result = bram_dout;
        endcase
    end

    always_comb begin
        cdb_trade = '{default: '0};
        if (ft_pipe.valid) begin
            cdb_trade.valid     = 1'b1;
            cdb_trade.result    = result;
            cdb_trade.rob_index = ft_pipe.rob_index;
            cdb_trade.rd_paddr  = ft_pipe.rd_paddr;
            cdb_trade.rd_addr   = ft_pipe.rd_addr;
        end
    end

endmodule : fetch_trade
