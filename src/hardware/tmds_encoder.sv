`timescale 1ns/1ps

module tmds_encoder (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] video_data,
    input  logic [1:0] control_data,
    input  logic       video_enable,
    output logic [9:0] tmds_data
);

    logic signed [4:0] disparity;

    function automatic logic [3:0] count_ones(input logic [7:0] value);
        begin
            count_ones = value[0] + value[1] + value[2] + value[3] +
                         value[4] + value[5] + value[6] + value[7];
        end
    endfunction

    always_ff @(posedge clk) begin
        if (rst) begin
            tmds_data <= 10'b1101010100;
            disparity <= '0;
        end else if (!video_enable) begin
            unique case (control_data)
                2'b00: tmds_data <= 10'b1101010100;
                2'b01: tmds_data <= 10'b0010101011;
                2'b10: tmds_data <= 10'b0101010100;
                default: tmds_data <= 10'b1010101011;
            endcase
            disparity <= '0;
        end else begin
            logic [8:0] q_m;
            logic [3:0] ones;
            logic use_xnor;
            logic signed [4:0] balance;

            ones = count_ones(video_data);
            use_xnor = (ones > 4) || ((ones == 4) && (video_data[0] == 1'b0));
            q_m[0] = video_data[0];
            for (int i = 1; i < 8; i++) begin
                q_m[i] = use_xnor ? ~(q_m[i-1] ^ video_data[i]) : (q_m[i-1] ^ video_data[i]);
            end
            q_m[8] = ~use_xnor;
            balance = $signed({1'b0, count_ones(q_m[7:0])}) - 5'sd4;

            if ((disparity == 0) || (balance == 0)) begin
                tmds_data[9] <= ~q_m[8];
                tmds_data[8] <= q_m[8];
                tmds_data[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
                disparity <= disparity + (q_m[8] ? balance : -balance);
            end else if ((disparity > 0 && balance > 0) || (disparity < 0 && balance < 0)) begin
                tmds_data[9] <= 1'b1;
                tmds_data[8] <= q_m[8];
                tmds_data[7:0] <= ~q_m[7:0];
                disparity <= disparity + $signed({3'b0, q_m[8], 1'b0}) - balance;
            end else begin
                tmds_data[9] <= 1'b0;
                tmds_data[8] <= q_m[8];
                tmds_data[7:0] <= q_m[7:0];
                disparity <= disparity - $signed({3'b0, ~q_m[8], 1'b0}) + balance;
            end
        end
    end

endmodule
