`timescale 1ns/1ps

module audio_clock_regeneration_fixed #(
    parameter int VIDEO_RATE_HZ = 25_200_000,
    parameter int AUDIO_RATE = 48_000
) (
    output logic [23:0] header,
    output logic [55:0] sub [3:0]
);

    localparam int N_VALUE =
        (AUDIO_RATE % 125 == 0) ? (16 * AUDIO_RATE / 125) :
        (AUDIO_RATE % 225 == 0) ? (32 * AUDIO_RATE / 225) :
                                  (16 * AUDIO_RATE / 125);
    localparam logic [63:0] VIDEO_RATE_HZ_64 = VIDEO_RATE_HZ;
    localparam logic [63:0] N_VALUE_64 = N_VALUE;
    localparam logic [63:0] CTS_NUM = VIDEO_RATE_HZ_64 * N_VALUE_64;
    localparam logic [63:0] CTS_DEN = 64'd128 * AUDIO_RATE;
    localparam int CTS_VALUE = (CTS_NUM + (CTS_DEN / 2)) / CTS_DEN;

    assign header = {8'd0, 8'd0, 8'd1};

    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : gen_same_packet
            assign sub[i] = {
                N_VALUE[7:0],
                N_VALUE[15:8],
                4'd0, N_VALUE[19:16],
                CTS_VALUE[7:0],
                CTS_VALUE[15:8],
                4'd0, CTS_VALUE[19:16],
                8'd0
            };
        end
    endgenerate

endmodule
