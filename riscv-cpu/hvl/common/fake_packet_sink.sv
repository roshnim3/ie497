// fake_packet_sink — testbench-side AXI-Stream sink for the pkt_tx FU.
//
// Captures every beat and emits one CSV row per packet (terminated by
// tlast). Always ready, no backpressure — Phase 1 doesn't exercise it.

module fake_packet_sink (
    input  logic        clk,
    input  logic        rst,
    input  logic        tvalid,
    input  logic [31:0] tdata,
    input  logic [3:0]  tkeep,
    input  logic        tlast,
    output logic        tready
);

    assign tready = 1'b1;

    localparam int MAX_BYTES = 4096;
    logic [7:0]  packet_bytes [MAX_BYTES];
    int          byte_count;
    int          packet_idx;
    int          fd;
    longint      pkt_first_cycle;
    longint      pkt_last_cycle;
    longint      sink_cycle;

    initial begin
        byte_count      = 0;
        packet_idx      = 0;
        pkt_first_cycle = -64'sd1;
        pkt_last_cycle  = -64'sd1;
        sink_cycle      = 64'd0;
        fd              = $fopen("tx_packets.csv", "w");
        if (fd != 0) begin
            $fdisplay(fd, "packet_idx,length,first_cycle,last_cycle,bytes_hex");
        end
    end

    always @(posedge clk) begin
        if (!rst) sink_cycle <= sink_cycle + 64'd1;
    end

    int bytes_this_beat;
    always @(posedge clk) begin
        if (rst) begin
            byte_count      <= 0;
            pkt_first_cycle <= -64'sd1;
        end else if (tvalid) begin
            // First beat in this packet?
            if (byte_count == 0) begin
                pkt_first_cycle <= sink_cycle;
            end

            // Decode tkeep into byte count for this beat.
            bytes_this_beat = 0;
            if (tkeep[0]) bytes_this_beat = 1;
            if (tkeep[1]) bytes_this_beat = 2;
            if (tkeep[2]) bytes_this_beat = 3;
            if (tkeep[3]) bytes_this_beat = 4;
            // (tkeep is contiguous LSB-first; we only support 0001 / 0011 / 0111 / 1111.)

            // Capture bytes (little-endian within the word).
            for (int i = 0; i < 4; i++) begin
                if (tkeep[i] && (byte_count + i) < MAX_BYTES) begin
                    packet_bytes[byte_count + i] = tdata[i*8 +: 8];
                end
            end
            byte_count <= byte_count + bytes_this_beat;

            if (tlast) begin
                pkt_last_cycle = sink_cycle;
                if (fd != 0) begin
                    $fwrite(fd, "%0d,%0d,%0d,%0d,",
                            packet_idx,
                            byte_count + bytes_this_beat,
                            pkt_first_cycle,
                            pkt_last_cycle);
                    for (int i = 0; i < byte_count + bytes_this_beat; i++) begin
                        $fwrite(fd, "%02X", packet_bytes[i]);
                    end
                    $fwrite(fd, "\n");
                    $fflush(fd);
                end
                packet_idx <= packet_idx + 1;
                byte_count <= 0;
            end
        end
    end

endmodule : fake_packet_sink
