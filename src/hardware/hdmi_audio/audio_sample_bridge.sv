`timescale 1ns/1ps

module audio_sample_bridge #(
    parameter int SYS_CLK_HZ = 100_000_000,
    parameter int AUDIO_RATE = 48_000,
    parameter int AUDIO_BITS = 16
) (
    input  logic                          clk,
    input  logic                          rst,
    input  logic signed [AUDIO_BITS-1:0]  pcm_l,
    input  logic signed [AUDIO_BITS-1:0]  pcm_r,
    output logic        [AUDIO_BITS-1:0]  audio_sample_l,
    output logic        [AUDIO_BITS-1:0]  audio_sample_r,
    output logic                          audio_sample_toggle
);

    localparam int BASE_DIV = SYS_CLK_HZ / AUDIO_RATE;
    localparam int REMAINDER = SYS_CLK_HZ % AUDIO_RATE;

    logic [31:0] sample_count;
    logic [31:0] error_accum;
    logic [31:0] error_next;

    assign error_next = error_accum + 32'(REMAINDER);

    always_ff @(posedge clk) begin
        if (rst) begin
            sample_count <= 32'd0;
            error_accum <= 32'd0;
            audio_sample_l <= '0;
            audio_sample_r <= '0;
            audio_sample_toggle <= 1'b0;
        end else if (sample_count == 32'd0) begin
            audio_sample_l <= pcm_l;
            audio_sample_r <= pcm_r;
            audio_sample_toggle <= ~audio_sample_toggle;
            if (error_next >= 32'(AUDIO_RATE)) begin
                error_accum <= error_next - 32'(AUDIO_RATE);
                sample_count <= 32'(BASE_DIV);
            end else begin
                error_accum <= error_next;
                sample_count <= 32'(BASE_DIV - 1);
            end
        end else begin
            sample_count <= sample_count - 1'b1;
        end
    end

endmodule
