`timescale 1ns/1ps

module tb_hdmi_audio_packetizer;

    localparam int H_ACTIVE = 640;
    localparam int H_FRONT_PORCH = 16;
    localparam int H_SYNC_PULSE = 96;
    localparam int H_BACK_PORCH = 48;
    localparam int V_ACTIVE = 480;
    localparam int V_FRONT_PORCH = 10;
    localparam int V_SYNC_PULSE = 2;
    localparam int V_BACK_PORCH = 33;
    localparam int H_TOTAL = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH;
    localparam int V_TOTAL = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [9:0] h_count;
    logic [9:0] v_count;
    logic hsync;
    logic vsync;
    logic de;
    logic [15:0] audio_l;
    logic [15:0] audio_r;
    logic audio_toggle;
    logic [9:0] tmds_ch0;
    logic [9:0] tmds_ch1;
    logic [9:0] tmds_ch2;
    int sample_div;
    bit saw_acr;
    bit saw_audio_sample;
    bit saw_audio_info;
    bit saw_avi;
    bit saw_terc4;
    bit saw_real_acr;
    bit saw_real_audio_sample;
    bit saw_real_audio_info;
    bit saw_real_avi;
    bit saw_four_packet_slots;
    bit done;
    int packet_slots_this_line;

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (reset) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= 10'd0;
            if (v_count == V_TOTAL - 1) begin
                v_count <= 10'd0;
            end else begin
                v_count <= v_count + 1'b1;
            end
        end else begin
            h_count <= h_count + 1'b1;
        end
    end

    always_comb begin
        de = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
        hsync = ~((h_count >= H_ACTIVE + H_FRONT_PORCH) &&
                  (h_count <  H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE));
        vsync = ~((v_count >= V_ACTIVE + V_FRONT_PORCH) &&
                  (v_count <  V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE));
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            sample_div <= 0;
            audio_l <= 16'sd0;
            audio_r <= 16'sd0;
            audio_toggle <= 1'b0;
        end else if (sample_div == 599) begin
            sample_div <= 0;
            audio_l <= audio_l + 16'sd257;
            audio_r <= audio_r - 16'sd193;
            audio_toggle <= ~audio_toggle;
        end else begin
            sample_div <= sample_div + 1;
        end
    end

    hdmi_external_video_encoder #(
        .H_ACTIVE(H_ACTIVE),
        .H_FRONT_PORCH(H_FRONT_PORCH),
        .H_SYNC_PULSE(H_SYNC_PULSE),
        .H_BACK_PORCH(H_BACK_PORCH),
        .V_ACTIVE(V_ACTIVE),
        .V_FRONT_PORCH(V_FRONT_PORCH),
        .V_SYNC_PULSE(V_SYNC_PULSE),
        .V_BACK_PORCH(V_BACK_PORCH),
        .VIDEO_ID_CODE(1),
        .VIDEO_RATE_HZ(25_200_000),
        .AUDIO_RATE(48_000),
        .AUDIO_BIT_WIDTH(16),
        .ENABLE_HDMI_AUDIO(1'b1)
    ) dut (
        .clk_pixel(clk),
        .reset(reset),
        .red(8'h40),
        .green(8'h80),
        .blue(8'hC0),
        .hsync(hsync),
        .vsync(vsync),
        .de(de),
        .audio_sample_l(audio_l),
        .audio_sample_r(audio_r),
        .audio_sample_toggle(audio_toggle),
        .tmds_ch0(tmds_ch0),
        .tmds_ch1(tmds_ch1),
        .tmds_ch2(tmds_ch2)
    );

    always_ff @(posedge clk) begin
        if (!reset) begin
            if (dut.data_island_preamble && dut.control_hsync != 1'b1) begin
                $fatal(1, "Data-island preamble crossed hsync at h=%0d v=%0d", dut.h_count, dut.v_count);
            end

            if (dut.h_count == 0) begin
                packet_slots_this_line <= 0;
            end else if (dut.packet_enable) begin
                packet_slots_this_line <= packet_slots_this_line + 1;
            end
            if (dut.h_count == H_TOTAL - 1 && packet_slots_this_line >= 4) begin
                saw_four_packet_slots <= 1'b1;
            end

            if (dut.mode == 3'd3) begin
                saw_terc4 <= 1'b1;
            end
            unique case (dut.packet_picker_i.packet_type)
                8'h01: begin
                    saw_acr <= 1'b1;
                    saw_real_acr <= saw_real_acr || (dut.header_to_assembler[7:0] == 8'h01);
                end
                8'h02: begin
                    saw_audio_sample <= 1'b1;
                    saw_real_audio_sample <= saw_real_audio_sample || (dut.header_to_assembler[7:0] == 8'h02);
                end
                8'h82: begin
                    saw_avi <= 1'b1;
                    saw_real_avi <= saw_real_avi || (dut.header_to_assembler[7:0] == 8'h82);
                end
                8'h84: begin
                    saw_audio_info <= 1'b1;
                    saw_real_audio_info <= saw_real_audio_info || (dut.header_to_assembler[7:0] == 8'h84);
                end
                default: begin end
            endcase
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        reset = 1'b0;
        for (int i = 0; i < 2_000_000; i++) begin
            @(posedge clk);
            if (saw_acr && saw_audio_sample && saw_audio_info && saw_avi && saw_terc4 &&
                saw_real_acr && saw_real_audio_sample && saw_real_audio_info && saw_real_avi &&
                saw_four_packet_slots) begin
                $display("tb_hdmi_audio_packetizer PASS");
                done = 1'b1;
                i = 2_000_000;
            end
        end
        if (!done) begin
            $fatal(1, "HDMI audio packetizer missing packet(s): acr=%0d/%0d sample=%0d/%0d audio_info=%0d/%0d avi=%0d/%0d terc4=%0d slots4=%0d",
                   saw_acr, saw_real_acr,
                   saw_audio_sample, saw_real_audio_sample,
                   saw_audio_info, saw_real_audio_info,
                   saw_avi, saw_real_avi,
                   saw_terc4, saw_four_packet_slots);
        end
        $finish;
    end

endmodule
