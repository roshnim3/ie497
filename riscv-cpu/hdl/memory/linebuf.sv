module linebuf (
    input logic clk,
    input logic rst,

    input logic [26:0]  tagin,
    input logic [255:0] din,
    input logic wr_en,

    output logic [26:0]  tagout,
    output logic [255:0] dout
);

    always_ff @(posedge clk ) begin
        if (rst) begin
            tagout <= '0;
            dout <= '0;
        end else if (wr_en) begin
            tagout <= tagin;
            dout <= din;
        end
    end

endmodule