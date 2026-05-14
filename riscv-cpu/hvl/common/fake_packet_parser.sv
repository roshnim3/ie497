// fake_packet_parser — behavioral model that drives Port A of the
// fetch_trade BRAM with a stream of varied ITCH-like packets. Lives in HVL
// so it doesn't have to follow synth constraints; this is sim-only.
//
// Behavior:
//   - Cycles through an N-entry packet ROM with varied prices, sides,
//     and shares values.
//   - Each packet is written to the BRAM as a 5-cycle burst:
//       phase 0 -> slot 0 (msg_type)
//       phase 1 -> slot 1 (side)
//       phase 2 -> slot 6 (shares)
//       phase 3 -> slot 7 (price)
//       phase 4 -> slot 3 (sequence number)  <-- "publish" cycle
//   - The seq slot is written last; the `commit` pulse fires on the same
//     cycle and tells the fetch_trade FU to advance head_ptr, making the
//     completed packet visible at the FIFO tail.
//   - After the 5-cycle burst, idles for (interval - 5) cycles before the
//     next packet, simulating inter-arrival time.

module fake_packet_parser
(
    input  logic        clk,
    input  logic        rst,
    input  logic        enable,
    input  logic [31:0] interval,   // CPU cycles between packet starts (>= 5)

    output logic        we,
    output logic [2:0]  addr,
    output logic [31:0] data,
    output logic        commit       // pulse on the slot-3 publish cycle
);

    localparam int NUM_PACKETS = 8;

    // ROM of varied packets. All msg_type='A' (0x41) except packet 3 which
    // tests the "not a Add Order, skip" branch in the firmware.
    logic [31:0] rom_msg_type [NUM_PACKETS];
    logic [31:0] rom_side     [NUM_PACKETS];
    logic [31:0] rom_shares   [NUM_PACKETS];
    logic [31:0] rom_price    [NUM_PACKETS];

    initial begin
        rom_msg_type[0] = 32'h41; rom_side[0] = 32'h42; rom_shares[0] = 32'd1000; rom_price[0] = 32'd100000;
        rom_msg_type[1] = 32'h41; rom_side[1] = 32'h42; rom_shares[1] = 32'd500;  rom_price[1] = 32'd200000;
        rom_msg_type[2] = 32'h41; rom_side[2] = 32'h53; rom_shares[2] = 32'd2000; rom_price[2] = 32'd99000;
        rom_msg_type[3] = 32'h44; rom_side[3] = 32'h42; rom_shares[3] = 32'd300;  rom_price[3] = 32'd80000;
        rom_msg_type[4] = 32'h41; rom_side[4] = 32'h42; rom_shares[4] = 32'd1500; rom_price[4] = 32'd120000;
        rom_msg_type[5] = 32'h41; rom_side[5] = 32'h53; rom_shares[5] = 32'd2500; rom_price[5] = 32'd95000;
        rom_msg_type[6] = 32'h41; rom_side[6] = 32'h42; rom_shares[6] = 32'd800;  rom_price[6] = 32'd110000;
        rom_msg_type[7] = 32'h41; rom_side[7] = 32'h53; rom_shares[7] = 32'd1200; rom_price[7] = 32'd105000;
    end

    logic [31:0] packet_idx;
    logic [31:0] phase;
    logic [31:0] seq_num;        // next seq to publish (starts at 2 since
                                 // packet 0 with seq=1 is preloaded by the
                                 // FU's MEMORY_INIT_PARAM).
    logic [2:0]  rom_idx;
    assign rom_idx = packet_idx[2:0];   // NUM_PACKETS=8 wraps naturally

    always_ff @(posedge clk) begin
        if (rst) begin
            packet_idx <= 32'd0;
            phase      <= 32'd0;
            seq_num    <= 32'd2;
        end else if (enable) begin
            if (phase >= interval - 32'd1) begin
                phase      <= 32'd0;
                packet_idx <= packet_idx + 32'd1;
                seq_num    <= seq_num + 32'd1;
            end else begin
                phase <= phase + 32'd1;
            end
        end
    end

    always_comb begin
        we     = 1'b0;
        addr   = 3'b0;
        data   = 32'b0;
        commit = 1'b0;
        if (enable) begin
            if (phase == 32'd0) begin
                we = 1'b1; addr = 3'd0; data = rom_msg_type[rom_idx];
            end else if (phase == 32'd1) begin
                we = 1'b1; addr = 3'd1; data = rom_side[rom_idx];
            end else if (phase == 32'd2) begin
                we = 1'b1; addr = 3'd6; data = rom_shares[rom_idx];
            end else if (phase == 32'd3) begin
                we = 1'b1; addr = 3'd7; data = rom_price[rom_idx];
            end else if (phase == 32'd4) begin
                we = 1'b1; addr = 3'd3; data = seq_num;
                commit = 1'b1;
            end
        end
    end

endmodule : fake_packet_parser
