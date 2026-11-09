`timescale 1ns / 1ps

module p4_hdmi_oserdes10 (
    input  wire [9:0] parallel_data,
    input  wire       reset,
    input  wire       parallel_clk,
    input  wire       pixel_clk_5x,
    input  wire       pixel_clk_2p5x,
    output wire       serial_data_out
);

reg  [3:0] wr_addr = 4'd0;
reg  [3:0] rd_addr = 4'd0;
wire [9:0] rd_curr;
reg  [9:0] tx_word = 10'd0;
reg  [2:0] bit_pair = 3'd0;

always @(posedge parallel_clk) begin
    if (reset) begin
        wr_addr <= 4'd0;
    end else begin
        wr_addr <= wr_addr + 1'b1;
    end
end

always @(posedge pixel_clk_5x) begin
    if (reset) begin
        rd_addr <= 4'd0;
        tx_word <= 10'd0;
        bit_pair <= 3'd0;
    end else begin
        if (bit_pair == 3'd4) begin
            bit_pair <= 3'd0;
            tx_word <= rd_curr;
            rd_addr <= rd_addr + 1'b1;
        end else begin
            bit_pair <= bit_pair + 1'b1;
        end
    end
end

genvar i;
generate
    for (i = 0; i < 10; i = i + 1) begin : gen_bit_ram
        RAM32X1D u_mem (
            .D(parallel_data[i]),
            .WCLK(parallel_clk),
            .WE(!reset),
            .A0(wr_addr[0]),
            .A1(wr_addr[1]),
            .A2(wr_addr[2]),
            .A3(wr_addr[3]),
            .A4(1'b0),
            .SPO(),
            .DPRA0(rd_addr[0]),
            .DPRA1(rd_addr[1]),
            .DPRA2(rd_addr[2]),
            .DPRA3(rd_addr[3]),
            .DPRA4(1'b0),
            .DPO(rd_curr[i])
        );
    end
endgenerate

wire oddr_d1;
wire oddr_d2;

assign oddr_d1 = (bit_pair == 3'd0) ? tx_word[0] :
                 (bit_pair == 3'd1) ? tx_word[2] :
                 (bit_pair == 3'd2) ? tx_word[4] :
                 (bit_pair == 3'd3) ? tx_word[6] :
                                      tx_word[8];

assign oddr_d2 = (bit_pair == 3'd0) ? tx_word[1] :
                 (bit_pair == 3'd1) ? tx_word[3] :
                 (bit_pair == 3'd2) ? tx_word[5] :
                 (bit_pair == 3'd3) ? tx_word[7] :
                                      tx_word[9];

ODDRE1 #(
    .IS_C_INVERTED(1'b0),
    .IS_D1_INVERTED(1'b0),
    .IS_D2_INVERTED(1'b0),
    .SIM_DEVICE("ULTRASCALE_PLUS"),
    .SRVAL(1'b0)
) u_oddr (
    .Q(serial_data_out),
    .C(pixel_clk_5x),
    .D1(oddr_d1),
    .D2(oddr_d2),
    .SR(reset)
);

endmodule
