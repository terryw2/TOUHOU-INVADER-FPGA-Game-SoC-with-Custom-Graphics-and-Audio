`timescale 1ns/1ps

module cdc_bit_sync_bd (
    input  wire clk,
    input  wire async_i,
    output wire sync_o
);

    (* ASYNC_REG = "TRUE" *) reg [2:0] sync_pipe = 3'b000;

    always @(posedge clk) begin
        sync_pipe <= {sync_pipe[1:0], async_i};
    end

    assign sync_o = sync_pipe[2];

endmodule
