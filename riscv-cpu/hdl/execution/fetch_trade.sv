// fetch_trade FU — custom-1 instruction backend.
//
// Reads one parser-output field from the parsed-fields memory and emits the
// result onto the mul/div CDB lane. Storage is an XPM_MEMORY SDPRAM
// primitive (Port A: parser writes [tied off in sim], Port B: CPU reads).
// 1-cycle registered read + 1-cycle packet pipeline alignment, so total
// RS-to-CDB latency is 2 cycles.
//
// MEMORY_INIT_PARAM holds the same ITCH Add Order values Sim B previously
// hard-coded into the ALU LUT array, so cycle counts compare directly.

module fetch_trade
import ooo_types::*;
(
    input  logic              clk,
    input  logic              rst,
    input  logic              flush,
    input  fu_fetch_trade_pkt ft_pkt,

    // Parser write side (Port A of the parsed-fields BRAM). Common-clock
    // for now; would move to independent-clock CDC when wiring up the
    // OpenNIC parser hardware. Tie off in non-streaming benchmarks.
    input  logic              parser_we,
    input  logic [2:0]        parser_addr,
    input  logic [31:0]       parser_data,

    output cdb_mul_div_pkt    cdb_trade
);

    logic [31:0] bram_dout;
    fu_fetch_trade_pkt ft_pipe;

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A           (3),
        .ADDR_WIDTH_B           (3),
        .AUTO_SLEEP_TIME        (0),
        .BYTE_WRITE_WIDTH_A     (32),
        .CASCADE_HEIGHT         (0),
        .CLOCKING_MODE          ("common_clock"),
        .ECC_MODE               ("no_ecc"),
        .MEMORY_INIT_FILE       ("none"),
        // 8 entries, address 0 first:
        //   0:msg_type 1:side ('B'=0x42 / 'S'=0x53) 2:tslo 3:tshi
        //   4:rnlo 5:rnhi 6:shares 7:price
        .MEMORY_INIT_PARAM      ("00000041,00000042,00ABCDEF,00000000,DEADBEEF,00000000,000003E8,000186A0"),
        .MEMORY_OPTIMIZATION    ("true"),
        .MEMORY_PRIMITIVE       ("block"),
        .MEMORY_SIZE            (256),       // 8 entries x 32 bits
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
        // Port A — parser write side.
        .clka                   (clk),
        .ena                    (parser_we),
        .wea                    (parser_we),
        .addra                  (parser_addr),
        .dina                   (parser_data),
        .injectsbiterra         (1'b0),
        .injectdbiterra         (1'b0),
        // Port B — CPU read side, driven by the field index.
        .clkb                   (clk),
        .rstb                   (rst),
        .enb                    (1'b1),
        .regceb                 (1'b1),
        .addrb                  (ft_pkt.field_idx),
        .doutb                  (bram_dout),
        .sbiterrb               (),
        .dbiterrb               ()
    );

    // Carry the packet metadata alongside the BRAM read so it lines up
    // with doutb when we drive the CDB.
    always_ff @(posedge clk) begin
        if (rst || flush) ft_pipe <= '0;
        else              ft_pipe <= ft_pkt;
    end

    always_comb begin
        cdb_trade = '{default: '0};
        if (ft_pipe.valid) begin
            cdb_trade.valid     = 1'b1;
            cdb_trade.result    = bram_dout;
            cdb_trade.rob_index = ft_pipe.rob_index;
            cdb_trade.rd_paddr  = ft_pipe.rd_paddr;
            cdb_trade.rd_addr   = ft_pipe.rd_addr;
        end
    end

endmodule : fetch_trade
