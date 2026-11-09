`timescale 1ns/1ps

module audio_engine #(
    parameter int C_S_AXI_ADDR_WIDTH = 6,
    parameter int C_S_AXI_DATA_WIDTH = 32
) (
    input  logic                              s_axi_aclk,
    input  logic                              s_axi_aresetn,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  logic [2:0]                        s_axi_awprot,
    input  logic                              s_axi_awvalid,
    output logic                              s_axi_awready,
    input  logic [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  logic                              s_axi_wvalid,
    output logic                              s_axi_wready,
    output logic [1:0]                        s_axi_bresp,
    output logic                              s_axi_bvalid,
    input  logic                              s_axi_bready,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  logic [2:0]                        s_axi_arprot,
    input  logic                              s_axi_arvalid,
    output logic                              s_axi_arready,
    output logic [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output logic [1:0]                        s_axi_rresp,
    output logic                              s_axi_rvalid,
    input  logic                              s_axi_rready,

    output logic                              spkl,
    output logic                              spkr,
    output logic [7:0]                        audio_debug,
    output logic signed [15:0]                pcm_l,
    output logic signed [15:0]                pcm_r
);

    localparam int NUM_CHANNELS = 3;
    localparam logic [3:0] CONTROL_WORD = 4'd0;
    localparam int CH_WORD_BASE = 1;
    localparam int CH_WORD_STRIDE = 4;
    localparam logic [3:0] STATUS_WORD = 4'd13;
    localparam int CLK_HZ = 100_000_000;
    localparam int MS_TICK_DIV = CLK_HZ / 1000;
    localparam logic [16:0] MS_TICK_MAX = 17'(MS_TICK_DIV - 1);

    logic [C_S_AXI_ADDR_WIDTH-1:0] awaddr_latched;
    logic [C_S_AXI_DATA_WIDTH-1:0] wdata_latched;
    logic [(C_S_AXI_DATA_WIDTH/8)-1:0] wstrb_latched;
    logic have_aw;
    logic have_w;
    logic [23:0] ch_period [NUM_CHANNELS];
    logic [7:0] ch_volume [NUM_CHANNELS];
    logic [15:0] ch_duration_ms [NUM_CHANNELS];
    logic [1:0] ch_pan [NUM_CHANNELS];
    logic [23:0] tone_count [NUM_CHANNELS];
    logic ch_tone [NUM_CHANNELS];
    logic audio_enable;
    logic [16:0] ms_tick_count;
    logic ms_tick;
    logic [7:0] pwm_count;

    wire [3:0] aw_word = awaddr_latched[5:2];
    wire [3:0] ar_word = s_axi_araddr[5:2];
    wire write_ready = have_aw && have_w && !s_axi_bvalid;

    function automatic logic [31:0] apply_wstrb(
        input logic [31:0] old_value,
        input logic [31:0] new_value,
        input logic [3:0]  strobe
    );
        logic [31:0] merged;
        begin
            merged = old_value;
            for (int i = 0; i < 4; i++) begin
                if (strobe[i]) begin
                    merged[i*8 +: 8] = new_value[i*8 +: 8];
                end
            end
            apply_wstrb = merged;
        end
    endfunction

    function automatic logic [31:0] channel_word(
        input int channel,
        input int field
    );
        begin
            unique case (field)
                0: channel_word = {8'h0, ch_period[channel]};
                1: channel_word = {24'h0, ch_volume[channel]};
                2: channel_word = {16'h0, ch_duration_ms[channel]};
                3: channel_word = {30'h0, ch_pan[channel]};
                default: channel_word = 32'h0;
            endcase
        end
    endfunction

    function automatic logic signed [15:0] pcm_from_mix(
        input logic signed [10:0] mix
    );
        logic signed [8:0] clipped;
        logic signed [15:0] extended;
        begin
            if (mix > 11'sd127) begin
                clipped = 9'sd127;
            end else if (mix < -11'sd128) begin
                clipped = -9'sd128;
            end else begin
                clipped = mix[8:0];
            end
            extended = {{7{clipped[8]}}, clipped};
            pcm_from_mix = extended <<< 8;
        end
    endfunction

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_arready <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= 32'h0;
            s_axi_rresp <= 2'b00;
            awaddr_latched <= '0;
            wdata_latched <= '0;
            wstrb_latched <= '0;
            have_aw <= 1'b0;
            have_w <= 1'b0;
            audio_enable <= 1'b0;
            for (int i = 0; i < NUM_CHANNELS; i++) begin
                ch_period[i] <= 24'd0;
                ch_volume[i] <= 8'd0;
                ch_duration_ms[i] <= 16'd0;
                ch_pan[i] <= 2'd0;
            end
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_arready <= 1'b0;

            if (!have_aw && s_axi_awvalid) begin
                awaddr_latched <= s_axi_awaddr;
                have_aw <= 1'b1;
                s_axi_awready <= 1'b1;
            end

            if (!have_w && s_axi_wvalid) begin
                wdata_latched <= s_axi_wdata;
                wstrb_latched <= s_axi_wstrb;
                have_w <= 1'b1;
                s_axi_wready <= 1'b1;
            end

            if (write_ready) begin
                logic [31:0] merged;
                merged = 32'h0;
                unique case (aw_word)
                    CONTROL_WORD: begin
                        merged = apply_wstrb({31'h0, audio_enable}, wdata_latched, wstrb_latched);
                        audio_enable <= merged[0];
                    end
                    default: begin
                        for (int ch = 0; ch < NUM_CHANNELS; ch++) begin
                            for (int field = 0; field < CH_WORD_STRIDE; field++) begin
                                if (aw_word == 4'(CH_WORD_BASE + ch * CH_WORD_STRIDE + field)) begin
                                    merged = apply_wstrb(channel_word(ch, field), wdata_latched, wstrb_latched);
                                    unique case (field)
                                        0: ch_period[ch] <= merged[23:0];
                                        1: ch_volume[ch] <= merged[7:0];
                                        2: ch_duration_ms[ch] <= merged[15:0];
                                        3: ch_pan[ch] <= merged[1:0];
                                        default: begin end
                                    endcase
                                end
                            end
                        end
                    end
                endcase
                have_aw <= 1'b0;
                have_w <= 1'b0;
                s_axi_bresp <= 2'b00;
                s_axi_bvalid <= 1'b1;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (!s_axi_rvalid && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                unique case (ar_word)
                    CONTROL_WORD: s_axi_rdata <= {31'h0, audio_enable};
                    STATUS_WORD:  s_axi_rdata <= 32'h41554430;
                    default: begin
                        s_axi_rdata <= 32'h0;
                        for (int ch = 0; ch < NUM_CHANNELS; ch++) begin
                            for (int field = 0; field < CH_WORD_STRIDE; field++) begin
                                if (ar_word == 4'(CH_WORD_BASE + ch * CH_WORD_STRIDE + field)) begin
                                    s_axi_rdata <= channel_word(ch, field);
                                end
                            end
                        end
                    end
                endcase
                s_axi_rresp <= 2'b00;
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end

            if (!audio_enable) begin
                for (int i = 0; i < NUM_CHANNELS; i++) begin
                    ch_volume[i] <= 8'd0;
                    ch_duration_ms[i] <= 16'd0;
                end
            end else if (ms_tick) begin
                for (int i = 0; i < NUM_CHANNELS; i++) begin
                    if (ch_duration_ms[i] != 16'd0) begin
                        ch_duration_ms[i] <= ch_duration_ms[i] - 1'b1;
                        if (ch_duration_ms[i] == 16'd1) begin
                            ch_volume[i] <= 8'd0;
                        end
                    end
                end
            end
        end
    end

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            ms_tick_count <= '0;
            ms_tick <= 1'b0;
        end else if (ms_tick_count == MS_TICK_MAX) begin
            ms_tick_count <= '0;
            ms_tick <= 1'b1;
        end else begin
            ms_tick_count <= ms_tick_count + 1'b1;
            ms_tick <= 1'b0;
        end
    end

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn || !audio_enable) begin
            for (int i = 0; i < NUM_CHANNELS; i++) begin
                tone_count[i] <= 24'd0;
                ch_tone[i] <= 1'b0;
            end
        end else begin
            for (int i = 0; i < NUM_CHANNELS; i++) begin
                if (ch_duration_ms[i] == 16'd0 || ch_period[i] == 24'd0 || ch_volume[i] == 8'd0) begin
                    tone_count[i] <= 24'd0;
                    ch_tone[i] <= 1'b0;
                end else if (tone_count[i] >= ch_period[i]) begin
                    tone_count[i] <= 24'd0;
                    ch_tone[i] <= ~ch_tone[i];
                end else begin
                    tone_count[i] <= tone_count[i] + 1'b1;
                end
            end
        end
    end

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            pwm_count <= 8'd0;
        end else begin
            pwm_count <= pwm_count + 1'b1;
        end
    end

    always_comb begin
        logic [9:0] left_mix;
        logic [9:0] right_mix;
        logic signed [10:0] left_pcm_mix;
        logic signed [10:0] right_pcm_mix;
        logic signed [8:0] signed_volume;
        logic signed [10:0] signed_volume_ext;
        logic [9:0] unsigned_volume_ext;
        logic [7:0] left_sample;
        logic [7:0] right_sample;

        left_mix = 10'd0;
        right_mix = 10'd0;
        left_pcm_mix = 11'sd0;
        right_pcm_mix = 11'sd0;
        for (int i = 0; i < NUM_CHANNELS; i++) begin
            if (audio_enable && ch_duration_ms[i] != 16'd0 && ch_volume[i] != 8'd0) begin
                signed_volume = ch_tone[i] ? $signed({1'b0, ch_volume[i]}) :
                                             -$signed({1'b0, ch_volume[i]});
                signed_volume_ext = {{2{signed_volume[8]}}, signed_volume};
                unsigned_volume_ext = {2'b00, ch_volume[i]};
                unique case (ch_pan[i])
                    2'd1: begin
                        left_pcm_mix = left_pcm_mix + signed_volume_ext;
                        if (ch_tone[i]) left_mix = left_mix + unsigned_volume_ext;
                    end
                    2'd2: begin
                        right_pcm_mix = right_pcm_mix + signed_volume_ext;
                        if (ch_tone[i]) right_mix = right_mix + unsigned_volume_ext;
                    end
                    default: begin
                        left_pcm_mix = left_pcm_mix + signed_volume_ext;
                        right_pcm_mix = right_pcm_mix + signed_volume_ext;
                        if (ch_tone[i]) begin
                            left_mix = left_mix + unsigned_volume_ext;
                            right_mix = right_mix + unsigned_volume_ext;
                        end
                    end
                endcase
            end
        end

        left_sample = (left_mix > 10'd255) ? 8'hFF : left_mix[7:0];
        right_sample = (right_mix > 10'd255) ? 8'hFF : right_mix[7:0];
        spkl = (pwm_count < left_sample);
        spkr = (pwm_count < right_sample);
        pcm_l = pcm_from_mix(left_pcm_mix);
        pcm_r = pcm_from_mix(right_pcm_mix);
        audio_debug = {
            ms_tick,
            |{ch_duration_ms[0], ch_duration_ms[1], ch_duration_ms[2]},
            audio_enable,
            ch_tone[2],
            ch_tone[1],
            ch_tone[0],
            spkr,
            spkl
        };
    end

endmodule
