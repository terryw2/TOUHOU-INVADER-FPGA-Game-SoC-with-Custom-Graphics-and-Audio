`timescale 1ns/1ps

module hdmi_tmds_tx #(
    parameter int H_ACTIVE = 640,
    parameter int H_FRONT_PORCH = 16,
    parameter int H_SYNC_PULSE = 96,
    parameter int H_BACK_PORCH = 48,
    parameter int V_ACTIVE = 480,
    parameter int V_FRONT_PORCH = 10,
    parameter int V_SYNC_PULSE = 2,
    parameter int V_BACK_PORCH = 33,
    parameter int VIDEO_ID_CODE = 1,
    parameter int VIDEO_RATE_HZ = 25_200_000,
    parameter bit ENABLE_HDMI_AUDIO = 1'b1
) (
    input  logic       pixel_clk,
    input  logic       bit_clk,
    input  logic       rst,
    input  logic [3:0] red,
    input  logic [3:0] green,
    input  logic [3:0] blue,
    input  logic       hsync,
    input  logic       vsync,
    input  logic       de,
    input  logic [15:0] audio_sample_l,
    input  logic [15:0] audio_sample_r,
    input  logic       audio_sample_toggle,
    output wire        hdmi_tmds_clk_p,
    output wire        hdmi_tmds_clk_n,
    output wire  [2:0] hdmi_tmds_data_p,
    output wire  [2:0] hdmi_tmds_data_n
);

    logic [9:0] encoded_r;
    logic [9:0] encoded_g;
    logic [9:0] encoded_b;
    logic [9:0] encoded_aux;

    generate
        if (ENABLE_HDMI_AUDIO) begin : gen_hdmi_audio_encoder
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
                .AUDIO_RATE(48_000),
                .AUDIO_BIT_WIDTH(16),
                .ENABLE_HDMI_AUDIO(ENABLE_HDMI_AUDIO)
            ) encoder_i (
                .clk_pixel(pixel_clk),
                .reset(rst),
                .red({red, red}),
                .green({green, green}),
                .blue({blue, blue}),
                .hsync(hsync),
                .vsync(vsync),
                .de(de),
                .audio_sample_l(audio_sample_l),
                .audio_sample_r(audio_sample_r),
                .audio_sample_toggle(audio_sample_toggle),
                .tmds_ch0(encoded_b),
                .tmds_ch1(encoded_g),
                .tmds_ch2(encoded_r)
            );
        end else begin : gen_dvi_video_encoder
            tmds_encoder blue_i (
                .clk(pixel_clk),
                .rst(rst),
                .video_data({blue, blue}),
                .control_data({vsync, hsync}),
                .video_enable(de),
                .tmds_data(encoded_b)
            );

            tmds_encoder green_i (
                .clk(pixel_clk),
                .rst(rst),
                .video_data({green, green}),
                .control_data(2'b00),
                .video_enable(de),
                .tmds_data(encoded_g)
            );

            tmds_encoder red_i (
                .clk(pixel_clk),
                .rst(rst),
                .video_data({red, red}),
                .control_data(2'b00),
                .video_enable(de),
                .tmds_data(encoded_r)
            );
        end
    endgenerate

    assign encoded_aux = 10'b1101010100;

    logic [3:0][9:0] shifter;
    logic [3:0] serial_out;
    logic [2:0] tmds_data_out;
    logic [3:0] bit_index;
    logic       load_symbol;

    always_ff @(posedge bit_clk) begin
        if (rst) begin
            bit_index <= 4'd0;
            load_symbol <= 1'b1;
            shifter[0] <= 10'b1101010100;
            shifter[1] <= 10'b1101010100;
            shifter[2] <= 10'b1101010100;
            shifter[3] <= 10'b1101010100;
            serial_out <= 4'h0;
        end else begin
            if (load_symbol) begin
                shifter[0] <= encoded_b;
                shifter[1] <= encoded_g;
                shifter[2] <= encoded_r;
                shifter[3] <= encoded_aux;
                serial_out <= {encoded_aux[0], encoded_r[0], encoded_g[0], encoded_b[0]};
                bit_index <= 4'd1;
                load_symbol <= 1'b0;
            end else begin
                for (int lane = 0; lane < 4; lane++) begin
                    shifter[lane] <= {1'b0, shifter[lane][9:1]};
                    serial_out[lane] <= shifter[lane][1];
                end
                if (bit_index == 4'd9) begin
                    bit_index <= 4'd0;
                    load_symbol <= 1'b1;
                end else begin
                    bit_index <= bit_index + 1'b1;
                    load_symbol <= 1'b0;
                end
            end
        end
    end

    always_ff @(posedge bit_clk) begin
        if (rst) begin
            tmds_data_out <= 3'h0;
        end else begin
            tmds_data_out <= serial_out[2:0];
        end
    end

`ifdef XILINX_SIMULATOR
    assign hdmi_tmds_clk_p = pixel_clk;
    assign hdmi_tmds_clk_n = ~pixel_clk;
    assign hdmi_tmds_data_p = tmds_data_out;
    assign hdmi_tmds_data_n = ~tmds_data_out;
`else
    OBUFDS #(
        .IOSTANDARD("TMDS_33"),
        .SLEW("FAST")
    ) tmds_clk_obufds (
        .I(pixel_clk),
        .O(hdmi_tmds_clk_p),
        .OB(hdmi_tmds_clk_n)
    );

    genvar lane;
    generate
        for (lane = 0; lane < 3; lane = lane + 1) begin : gen_tmds_data_obufds
            OBUFDS #(
                .IOSTANDARD("TMDS_33"),
                .SLEW("FAST")
            ) tmds_data_obufds (
                .I(tmds_data_out[lane]),
                .O(hdmi_tmds_data_p[lane]),
                .OB(hdmi_tmds_data_n[lane])
            );
        end
    endgenerate
`endif

endmodule
