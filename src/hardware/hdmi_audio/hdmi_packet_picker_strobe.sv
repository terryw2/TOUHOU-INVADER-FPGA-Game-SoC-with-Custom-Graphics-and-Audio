`timescale 1ns/1ps

module hdmi_packet_picker_strobe #(
    parameter int VIDEO_ID_CODE = 1,
    parameter int VIDEO_RATE_HZ = 25_200_000,
    parameter bit IT_CONTENT = 1'b1,
    parameter int AUDIO_BIT_WIDTH = 16,
    parameter int AUDIO_RATE = 48_000,
    parameter bit [8*8-1:0] VENDOR_NAME = {"MICROBLA"},
    parameter bit [8*16-1:0] PRODUCT_DESCRIPTION = {"MB HDMI GAME", 32'd0},
    parameter bit [7:0] SOURCE_DEVICE_INFORMATION = 8'h08
) (
    input  logic clk_pixel,
    input  logic reset,
    input  logic video_field_end,
    input  logic packet_enable,
    input  logic [4:0] packet_pixel_counter,
    input  logic [AUDIO_BIT_WIDTH-1:0] audio_sample_l,
    input  logic [AUDIO_BIT_WIDTH-1:0] audio_sample_r,
    input  logic audio_sample_toggle,
    output logic [23:0] header,
    output logic [55:0] sub [3:0]
);

    localparam int AUDIO_SAMPLES_PER_ACR =
        (AUDIO_RATE >= 1000) ? (AUDIO_RATE / 1000) : 1;

    localparam bit [3:0] SAMPLING_FREQUENCY =
        AUDIO_RATE == 32000  ? 4'b0011 :
        AUDIO_RATE == 44100  ? 4'b0000 :
        AUDIO_RATE == 88200  ? 4'b1000 :
        AUDIO_RATE == 176400 ? 4'b1100 :
        AUDIO_RATE == 48000  ? 4'b0010 :
        AUDIO_RATE == 96000  ? 4'b1010 :
        AUDIO_RATE == 192000 ? 4'b1110 :
                               4'b0010;
    localparam int AUDIO_BIT_WIDTH_COMPARATOR =
        AUDIO_BIT_WIDTH < 20  ? 20 :
        AUDIO_BIT_WIDTH == 20 ? 25 :
        AUDIO_BIT_WIDTH < 24  ? 24 :
        AUDIO_BIT_WIDTH == 24 ? 29 : 20;
    localparam bit [2:0] WORD_LENGTH =
        3'(AUDIO_BIT_WIDTH_COMPARATOR - AUDIO_BIT_WIDTH);
    localparam bit WORD_LENGTH_LIMIT = AUDIO_BIT_WIDTH <= 20 ? 1'b0 : 1'b1;

    logic [7:0] packet_type;
    logic [23:0] header_acr;
    logic [23:0] header_audio_sample;
    logic [23:0] header_avi;
    logic [23:0] header_spd;
    logic [23:0] header_audio_info;
    logic [55:0] sub_acr [3:0];
    logic [55:0] sub_audio_sample [3:0];
    logic [55:0] sub_avi [3:0];
    logic [55:0] sub_spd [3:0];
    logic [55:0] sub_audio_info [3:0];

    always_comb begin
        header = 24'd0;
        for (int i = 0; i < 4; i++) begin
            sub[i] = 56'd0;
        end

        unique case (packet_type)
            8'h01: begin
                header = header_acr;
                for (int i = 0; i < 4; i++) sub[i] = sub_acr[i];
            end
            8'h02: begin
                header = header_audio_sample;
                for (int i = 0; i < 4; i++) sub[i] = sub_audio_sample[i];
            end
            8'h82: begin
                header = header_avi;
                for (int i = 0; i < 4; i++) sub[i] = sub_avi[i];
            end
            8'h83: begin
                header = header_spd;
                for (int i = 0; i < 4; i++) sub[i] = sub_spd[i];
            end
            8'h84: begin
                header = header_audio_info;
                for (int i = 0; i < 4; i++) sub[i] = sub_audio_info[i];
            end
            default: begin
                header = 24'd0;
                for (int i = 0; i < 4; i++) sub[i] = 56'd0;
            end
        endcase
    end

    audio_clock_regeneration_fixed #(
        .VIDEO_RATE_HZ(VIDEO_RATE_HZ),
        .AUDIO_RATE(AUDIO_RATE)
    ) audio_clock_regeneration_i (
        .header(header_acr),
        .sub(sub_acr)
    );

    logic [7:0] frame_counter;
    logic [23:0] audio_sample_word_packet [3:0] [1:0];
    logic [3:0] audio_sample_word_present_packet;
    logic [1:0] zero_bits [3:0];

    genvar zero_idx;
    generate
        for (zero_idx = 0; zero_idx < 4; zero_idx++) begin : gen_zero_bits
            assign zero_bits[zero_idx] = 2'b00;
        end
    endgenerate

    audio_sample_packet #(
        .SAMPLING_FREQUENCY(SAMPLING_FREQUENCY),
        .WORD_LENGTH({WORD_LENGTH[0], WORD_LENGTH[1], WORD_LENGTH[2], WORD_LENGTH_LIMIT})
    ) audio_sample_packet_i (
        .frame_counter(frame_counter),
        .valid_bit(zero_bits),
        .user_data_bit(zero_bits),
        .audio_sample_word(audio_sample_word_packet),
        .audio_sample_word_present(audio_sample_word_present_packet),
        .header(header_audio_sample),
        .sub(sub_audio_sample)
    );

    auxiliary_video_information_info_frame #(
        .VIDEO_ID_CODE(7'(VIDEO_ID_CODE)),
        .IT_CONTENT(IT_CONTENT)
    ) avi_info_frame_i (
        .header(header_avi),
        .sub(sub_avi)
    );

    source_product_description_info_frame #(
        .VENDOR_NAME(VENDOR_NAME),
        .PRODUCT_DESCRIPTION(PRODUCT_DESCRIPTION),
        .SOURCE_DEVICE_INFORMATION(SOURCE_DEVICE_INFORMATION)
    ) spd_info_frame_i (
        .header(header_spd),
        .sub(sub_spd)
    );

    audio_info_frame audio_info_frame_i (
        .header(header_audio_info),
        .sub(sub_audio_info)
    );

    logic [2:0] sample_toggle_sync;
    logic sample_edge;
    logic sample_buffer_current;
    logic [1:0] samples_remaining;
    logic [23:0] audio_sample_word_buffer [1:0] [3:0] [1:0];
    logic sample_buffer_used;
    logic sample_buffer_ready;

    assign sample_edge = sample_toggle_sync[2] ^ sample_toggle_sync[1];

    always_ff @(posedge clk_pixel) begin
        if (reset) begin
            sample_toggle_sync <= 3'd0;
        end else begin
            sample_toggle_sync <= {sample_toggle_sync[1:0], audio_sample_toggle};
        end
    end

    always_ff @(posedge clk_pixel) begin
        if (reset) begin
            sample_buffer_current <= 1'b0;
            samples_remaining <= 2'd0;
            sample_buffer_ready <= 1'b0;
            for (int b = 0; b < 2; b++) begin
                for (int s = 0; s < 4; s++) begin
                    audio_sample_word_buffer[b][s][0] <= 24'd0;
                    audio_sample_word_buffer[b][s][1] <= 24'd0;
                end
            end
        end else begin
            if (sample_buffer_used) begin
                sample_buffer_ready <= 1'b0;
            end

            if (sample_edge) begin
                audio_sample_word_buffer[sample_buffer_current][samples_remaining][0] <=
                    24'(audio_sample_l) << (24 - AUDIO_BIT_WIDTH);
                audio_sample_word_buffer[sample_buffer_current][samples_remaining][1] <=
                    24'(audio_sample_r) << (24 - AUDIO_BIT_WIDTH);
                if (samples_remaining == 2'd3) begin
                    samples_remaining <= 2'd0;
                    sample_buffer_ready <= 1'b1;
                    sample_buffer_current <= ~sample_buffer_current;
                end else begin
                    samples_remaining <= samples_remaining + 1'b1;
                end
            end
        end
    end

    logic audio_info_frame_sent;
    logic auxiliary_video_information_info_frame_sent;
    logic source_product_description_info_frame_sent;
    logic acr_due;
    logic [$clog2(AUDIO_SAMPLES_PER_ACR+1)-1:0] acr_sample_counter;

    always_ff @(posedge clk_pixel) begin
        if (reset) begin
            packet_type <= 8'd0;
            frame_counter <= 8'd0;
            audio_info_frame_sent <= 1'b0;
            auxiliary_video_information_info_frame_sent <= 1'b0;
            source_product_description_info_frame_sent <= 1'b0;
            audio_sample_word_present_packet <= 4'd0;
            sample_buffer_used <= 1'b0;
            acr_due <= 1'b1;
            acr_sample_counter <= '0;
            for (int s = 0; s < 4; s++) begin
                audio_sample_word_packet[s][0] <= 24'd0;
                audio_sample_word_packet[s][1] <= 24'd0;
            end
        end else begin
            sample_buffer_used <= 1'b0;

            if (sample_edge) begin
                if (acr_sample_counter == AUDIO_SAMPLES_PER_ACR-1) begin
                    acr_sample_counter <= '0;
                    acr_due <= 1'b1;
                end else begin
                    acr_sample_counter <= acr_sample_counter + 1'b1;
                end
            end

            if (packet_pixel_counter == 5'd31 && packet_type == 8'h02) begin
                frame_counter <= (frame_counter >= 8'd188) ?
                                 (frame_counter + 8'd4 - 8'd192) :
                                 (frame_counter + 8'd4);
            end

            if (video_field_end) begin
                audio_info_frame_sent <= 1'b0;
                auxiliary_video_information_info_frame_sent <= 1'b0;
                source_product_description_info_frame_sent <= 1'b0;
                packet_type <= 8'd0;
            end else if (packet_enable) begin
                if (acr_due) begin
                    packet_type <= 8'h01;
                    acr_due <= 1'b0;
                end else if (sample_buffer_ready) begin
                    packet_type <= 8'h02;
                    for (int s = 0; s < 4; s++) begin
                        audio_sample_word_packet[s][0] <= audio_sample_word_buffer[~sample_buffer_current][s][0];
                        audio_sample_word_packet[s][1] <= audio_sample_word_buffer[~sample_buffer_current][s][1];
                    end
                    audio_sample_word_present_packet <= 4'b1111;
                    sample_buffer_used <= 1'b1;
                end else if (!audio_info_frame_sent) begin
                    packet_type <= 8'h84;
                    audio_info_frame_sent <= 1'b1;
                end else if (!auxiliary_video_information_info_frame_sent) begin
                    packet_type <= 8'h82;
                    auxiliary_video_information_info_frame_sent <= 1'b1;
                end else if (!source_product_description_info_frame_sent) begin
                    packet_type <= 8'h83;
                    source_product_description_info_frame_sent <= 1'b1;
                end else begin
                    packet_type <= 8'd0;
                end
            end
        end
    end

endmodule
