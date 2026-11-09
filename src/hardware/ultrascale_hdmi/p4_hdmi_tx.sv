`timescale 1ns / 1ps

module p4_hdmi_tx #(
    parameter integer H_ACTIVE = 640,
    parameter integer H_FRONT_PORCH = 16,
    parameter integer H_SYNC_PULSE = 96,
    parameter integer H_BACK_PORCH = 48,
    parameter integer V_ACTIVE = 480,
    parameter integer V_FRONT_PORCH = 10,
    parameter integer V_SYNC_PULSE = 2,
    parameter integer V_BACK_PORCH = 33,
    parameter integer VIDEO_ID_CODE = 1,
    parameter integer VIDEO_RATE_HZ = 25200000,
    parameter ENABLE_HDMI_AUDIO = 1'b1
) (
    input  wire        pclk,
    input  wire        pixel_clk_5x,
    input  wire        pixel_clk_2p5x,
    input  wire        reset_n,
    input  wire [23:0] video_din,
    input  wire        video_hsync,
    input  wire        video_vsync,
    input  wire        video_de,
    input  wire [15:0] audio_sample_l,
    input  wire [15:0] audio_sample_r,
    input  wire        audio_sample_toggle,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,
    output wire [2:0]  tmds_data_n
);

wire reset;
p4_async_reset_sync u_reset_sync (
    .clk(pclk),
    .reset_n(reset_n),
    .reset(reset)
);

wire [9:0] red_10bit;
wire [9:0] green_10bit;
wire [9:0] blue_10bit;
wire [9:0] clk_10bit = 10'b1111100000;

hdmi_external_video_encoder #(
    .H_ACTIVE(H_ACTIVE),
    .H_FRONT_PORCH(H_FRONT_PORCH),
    .H_SYNC_PULSE(H_SYNC_PULSE),
    .H_BACK_PORCH(H_BACK_PORCH),
    .V_ACTIVE(V_ACTIVE),
    .V_FRONT_PORCH(V_FRONT_PORCH),
    .V_SYNC_PULSE(V_SYNC_PULSE),
    .V_BACK_PORCH(V_BACK_PORCH),
    .VIDEO_ID_CODE(VIDEO_ID_CODE),
    .VIDEO_RATE_HZ(VIDEO_RATE_HZ),
    .AUDIO_RATE(48000),
    .AUDIO_BIT_WIDTH(16),
    .ENABLE_HDMI_AUDIO(ENABLE_HDMI_AUDIO)
) u_encoder (
    .clk_pixel(pclk),
    .reset(reset),
    .red(video_din[23:16]),
    .green(video_din[15:8]),
    .blue(video_din[7:0]),
    .hsync(video_hsync),
    .vsync(video_vsync),
    .de(video_de),
    .audio_sample_l(audio_sample_l),
    .audio_sample_r(audio_sample_r),
    .audio_sample_toggle(audio_sample_toggle),
    .tmds_ch0(blue_10bit),
    .tmds_ch1(green_10bit),
    .tmds_ch2(red_10bit)
);

wire [2:0] tmds_data_serial;
wire       tmds_clk_serial;

p4_hdmi_oserdes10 u_serializer_b (
    .reset(reset),
    .parallel_clk(pclk),
    .pixel_clk_5x(pixel_clk_5x),
    .pixel_clk_2p5x(pixel_clk_2p5x),
    .parallel_data(blue_10bit),
    .serial_data_out(tmds_data_serial[0])
);

p4_hdmi_oserdes10 u_serializer_g (
    .reset(reset),
    .parallel_clk(pclk),
    .pixel_clk_5x(pixel_clk_5x),
    .pixel_clk_2p5x(pixel_clk_2p5x),
    .parallel_data(green_10bit),
    .serial_data_out(tmds_data_serial[1])
);

p4_hdmi_oserdes10 u_serializer_r (
    .reset(reset),
    .parallel_clk(pclk),
    .pixel_clk_5x(pixel_clk_5x),
    .pixel_clk_2p5x(pixel_clk_2p5x),
    .parallel_data(red_10bit),
    .serial_data_out(tmds_data_serial[2])
);

p4_hdmi_oserdes10 u_serializer_clk (
    .reset(reset),
    .parallel_clk(pclk),
    .pixel_clk_5x(pixel_clk_5x),
    .pixel_clk_2p5x(pixel_clk_2p5x),
    .parallel_data(clk_10bit),
    .serial_data_out(tmds_clk_serial)
);

OBUFDS u_tmds0 (
    .I(tmds_data_serial[0]),
    .O(tmds_data_p[0]),
    .OB(tmds_data_n[0])
);

OBUFDS u_tmds1 (
    .I(tmds_data_serial[1]),
    .O(tmds_data_p[1]),
    .OB(tmds_data_n[1])
);

OBUFDS u_tmds2 (
    .I(tmds_data_serial[2]),
    .O(tmds_data_p[2]),
    .OB(tmds_data_n[2])
);

OBUFDS u_tmds_clk (
    .I(tmds_clk_serial),
    .O(tmds_clk_p),
    .OB(tmds_clk_n)
);

endmodule
