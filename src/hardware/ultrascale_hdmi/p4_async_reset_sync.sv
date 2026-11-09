`timescale 1ns / 1ps

module p4_async_reset_sync (
    input  wire clk,
    input  wire reset_n,
    output wire reset
);

reg reset_1 = 1'b1;
reg reset_2 = 1'b1;

assign reset = reset_2;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        reset_1 <= 1'b1;
        reset_2 <= 1'b1;
    end else begin
        reset_1 <= 1'b0;
        reset_2 <= reset_1;
    end
end

endmodule
