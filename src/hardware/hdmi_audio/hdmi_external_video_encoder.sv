`timescale 1ns/1ps

module hdmi_external_video_encoder #(
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
    parameter int AUDIO_RATE = 48_000,
    parameter int AUDIO_BIT_WIDTH = 16,
    parameter bit ENABLE_HDMI_AUDIO = 1'b1
) (
    input  logic                          clk_pixel,
    input  logic                          reset,
    input  logic [7:0]                    red,
    input  logic [7:0]                    green,
    input  logic [7:0]                    blue,
    input  logic                          hsync,
    input  logic                          vsync,
    input  logic                          de,
    input  logic [AUDIO_BIT_WIDTH-1:0]    audio_sample_l,
    input  logic [AUDIO_BIT_WIDTH-1:0]    audio_sample_r,
    input  logic                          audio_sample_toggle,
    output logic [9:0]                    tmds_ch0,
    output logic [9:0]                    tmds_ch1,
    output logic [9:0]                    tmds_ch2
);

    localparam int H_TOTAL = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH;
    localparam int V_TOTAL = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH;
    localparam int DATA_ISLAND_CONTROL_PIXELS = 4;
    localparam int PREAMBLE_PIXELS = 8;
    localparam int GUARD_PIXELS = 2;
    localparam int VIDEO_PREAMBLE_START = H_TOTAL - PREAMBLE_PIXELS - GUARD_PIXELS;
    localparam int DATA_ISLAND_PREAMBLE_START = H_ACTIVE + DATA_ISLAND_CONTROL_PIXELS;
    localparam int DATA_ISLAND_GUARD_START = DATA_ISLAND_PREAMBLE_START + PREAMBLE_PIXELS;
    localparam int DATA_ISLAND_START = DATA_ISLAND_GUARD_START + GUARD_PIXELS;
    localparam int DATA_ISLAND_PACKET_ROOM = VIDEO_PREAMBLE_START -
                                             DATA_ISLAND_START -
                                             GUARD_PIXELS;
    localparam int PACKET_BUDGET = (DATA_ISLAND_PACKET_ROOM > 0) ?
                                   (DATA_ISLAND_PACKET_ROOM / 32) : 0;
    localparam int NUM_PACKETS = (PACKET_BUDGET > 18) ? 18 : PACKET_BUDGET;
    localparam int DATA_ISLAND_END = DATA_ISLAND_START + NUM_PACKETS * 32;

    logic [$clog2(H_TOTAL)-1:0] h_count;
    logic [$clog2(V_TOTAL)-1:0] v_count;
    logic de_d;
    logic line_had_de;
    logic saw_blank_line;
    logic de_rise;

    assign de_rise = de && !de_d;

    always_ff @(posedge clk_pixel) begin
        if (reset) begin
            h_count <= '0;
            v_count <= '0;
            de_d <= 1'b0;
            line_had_de <= 1'b0;
            saw_blank_line <= 1'b1;
        end else begin
            de_d <= de;

            if (de_rise) begin
                h_count <= '0;
                line_had_de <= 1'b1;
                saw_blank_line <= 1'b0;
                if (saw_blank_line) begin
                    v_count <= '0;
                end
            end else if (h_count == H_TOTAL - 1) begin
                h_count <= '0;
                line_had_de <= de;
                if (!line_had_de && !de) begin
                    saw_blank_line <= 1'b1;
                end
                if (v_count == V_TOTAL - 1) begin
                    v_count <= '0;
                end else begin
                    v_count <= v_count + 1'b1;
                end
            end else begin
                h_count <= h_count + 1'b1;
                line_had_de <= line_had_de || de;
            end
        end
    end

    logic video_data_period;
    logic data_island_period_instantaneous;
    logic data_island_period;
    logic packet_enable;
    logic data_island_guard;
    logic data_island_preamble;
    logic video_guard;
    logic video_preamble;
    logic video_field_end;

    localparam bit CEA_SYNC_INVERT =
        VIDEO_ID_CODE == 1  || VIDEO_ID_CODE == 2  || VIDEO_ID_CODE == 3 ||
        VIDEO_ID_CODE == 17 || VIDEO_ID_CODE == 18;
    localparam int HSYNC_START = H_ACTIVE + H_FRONT_PORCH;
    localparam int HSYNC_END = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE;
    localparam int VSYNC_START = V_ACTIVE + V_FRONT_PORCH;
    localparam int VSYNC_END = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE;

    logic hdmi_hsync;
    logic hdmi_vsync;
    logic control_hsync;
    logic control_vsync;

    always_comb begin
        hdmi_hsync = CEA_SYNC_INVERT ^
                     (h_count >= HSYNC_START && h_count < HSYNC_END);

        if (V_FRONT_PORCH > 0 && v_count == VSYNC_START - 1) begin
            hdmi_vsync = CEA_SYNC_INVERT ^ (h_count >= HSYNC_START);
        end else if (V_SYNC_PULSE > 0 && v_count == VSYNC_END - 1) begin
            hdmi_vsync = CEA_SYNC_INVERT ^ (h_count < HSYNC_START);
        end else begin
            hdmi_vsync = CEA_SYNC_INVERT ^
                         (v_count >= VSYNC_START && v_count < VSYNC_END);
        end
    end

    assign control_hsync = ENABLE_HDMI_AUDIO ? hdmi_hsync : hsync;
    assign control_vsync = ENABLE_HDMI_AUDIO ? hdmi_vsync : vsync;

    assign data_island_period_instantaneous = ENABLE_HDMI_AUDIO && NUM_PACKETS > 0 &&
                                              h_count >= DATA_ISLAND_START &&
                                              h_count < DATA_ISLAND_END;
    assign packet_enable = data_island_period_instantaneous &&
                           (((h_count - DATA_ISLAND_START) & 5'h1F) == 5'd0);
    assign video_field_end = h_count == H_ACTIVE - 1 && v_count == V_ACTIVE - 1;

    always_ff @(posedge clk_pixel) begin
        if (reset) begin
            video_data_period <= 1'b0;
            data_island_period <= 1'b0;
            data_island_guard <= 1'b0;
            data_island_preamble <= 1'b0;
            video_guard <= ENABLE_HDMI_AUDIO;
            video_preamble <= 1'b0;
        end else begin
            video_data_period <= de;
            data_island_period <= data_island_period_instantaneous;
            data_island_guard <= ENABLE_HDMI_AUDIO && NUM_PACKETS > 0 &&
                                 ((h_count >= DATA_ISLAND_GUARD_START && h_count < DATA_ISLAND_START) ||
                                  (h_count >= DATA_ISLAND_END && h_count < DATA_ISLAND_END + 2));
            data_island_preamble <= ENABLE_HDMI_AUDIO && NUM_PACKETS > 0 &&
                                    h_count >= DATA_ISLAND_PREAMBLE_START &&
                                    h_count < DATA_ISLAND_GUARD_START;
            video_guard <= ENABLE_HDMI_AUDIO &&
                           h_count >= H_TOTAL - 2 && h_count < H_TOTAL &&
                           (v_count == V_TOTAL - 1 || v_count < V_ACTIVE - 1);
            video_preamble <= ENABLE_HDMI_AUDIO &&
                              h_count >= VIDEO_PREAMBLE_START && h_count < H_TOTAL - 2 &&
                              (v_count == V_TOTAL - 1 || v_count < V_ACTIVE - 1);
        end
    end

    logic [23:0] header;
    logic [55:0] sub [3:0];
    logic [23:0] header_to_assembler;
    logic [55:0] sub_to_assembler [3:0];
    logic [8:0] packet_data;
    logic [4:0] packet_pixel_counter;

    hdmi_packet_picker_strobe #(
        .VIDEO_ID_CODE(VIDEO_ID_CODE),
        .VIDEO_RATE_HZ(VIDEO_RATE_HZ),
        .AUDIO_RATE(AUDIO_RATE),
        .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH)
    ) packet_picker_i (
        .clk_pixel(clk_pixel),
        .reset(reset),
        .video_field_end(video_field_end),
        .packet_enable(packet_enable),
        .packet_pixel_counter(packet_pixel_counter),
        .audio_sample_l(audio_sample_l),
        .audio_sample_r(audio_sample_r),
        .audio_sample_toggle(audio_sample_toggle),
        .header(header),
        .sub(sub)
    );

    packet_assembler packet_assembler_i (
        .clk_pixel(clk_pixel),
        .reset(reset),
        .data_island_period(data_island_period),
        .header(header_to_assembler),
        .sub(sub_to_assembler),
        .packet_data(packet_data),
        .counter(packet_pixel_counter)
    );

    always_comb begin
        header_to_assembler = header;
        for (int i = 0; i < 4; i++) begin
            sub_to_assembler[i] = sub[i];
        end
    end

    logic [2:0] mode;
    logic [23:0] video_data;
    logic [5:0] control_data;
    logic [11:0] data_island_data;

    always_ff @(posedge clk_pixel) begin
        if (reset) begin
            mode <= ENABLE_HDMI_AUDIO ? 3'd2 : 3'd0;
            video_data <= 24'd0;
            control_data <= 6'd0;
            data_island_data <= 12'd0;
        end else if (ENABLE_HDMI_AUDIO) begin
            mode <= data_island_guard ? 3'd4 :
                    data_island_period ? 3'd3 :
                    video_guard ? 3'd2 :
                    video_data_period ? 3'd1 : 3'd0;
            video_data <= {red, green, blue};
            control_data <= {{1'b0, data_island_preamble},
                             {1'b0, video_preamble || data_island_preamble},
                             {control_vsync, control_hsync}};
            data_island_data[11:4] <= packet_data[8:1];
            data_island_data[3] <= h_count != 0;
            data_island_data[2] <= packet_data[0];
            data_island_data[1:0] <= {control_vsync, control_hsync};
        end else begin
            mode <= video_data_period ? 3'd1 : 3'd0;
            video_data <= {red, green, blue};
            control_data <= {4'b0000, control_vsync, control_hsync};
            data_island_data <= 12'd0;
        end
    end

    tmds_channel #(.CN(0)) tmds_channel_b (
        .clk_pixel(clk_pixel),
        .video_data(video_data[7:0]),
        .data_island_data(data_island_data[3:0]),
        .control_data(control_data[1:0]),
        .mode(mode),
        .tmds(tmds_ch0)
    );

    tmds_channel #(.CN(1)) tmds_channel_g (
        .clk_pixel(clk_pixel),
        .video_data(video_data[15:8]),
        .data_island_data(data_island_data[7:4]),
        .control_data(control_data[3:2]),
        .mode(mode),
        .tmds(tmds_ch1)
    );

    tmds_channel #(.CN(2)) tmds_channel_r (
        .clk_pixel(clk_pixel),
        .video_data(video_data[23:16]),
        .data_island_data(data_island_data[11:8]),
        .control_data(control_data[5:4]),
        .mode(mode),
        .tmds(tmds_ch2)
    );

endmodule
