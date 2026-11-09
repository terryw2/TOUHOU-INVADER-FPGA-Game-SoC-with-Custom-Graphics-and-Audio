`timescale 1ns/1ps

module hdmi_clocking (
    input  logic sys_clk,
    input  logic reset,
    output logic pixel_clk,
    output logic bit_clk,
    output logic locked
);

`ifdef XILINX_SIMULATOR
    logic [1:0] div4;
    initial begin
        pixel_clk = 1'b0;
        bit_clk = 1'b0;
        locked = 1'b0;
        div4 = 2'b00;
        #200 locked = 1'b1;
    end

    always_ff @(posedge sys_clk) begin
        if (reset) begin
            div4 <= 2'b00;
            pixel_clk <= 1'b0;
            bit_clk <= 1'b0;
        end else begin
            div4 <= div4 + 1'b1;
            if (div4 == 2'b11) begin
                pixel_clk <= ~pixel_clk;
            end
            bit_clk <= ~bit_clk;
        end
    end
`else
    wire clkfb;
    wire pixel_clk_unbuf;
    wire bit_clk_unbuf;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(30.25),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(10.0),
        .CLKOUT0_DIVIDE_F(30.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(3),
        .CLKOUT1_DUTY_CYCLE(0.5),
        .CLKOUT1_PHASE(0.0),
        .DIVCLK_DIVIDE(4),
        .STARTUP_WAIT("FALSE")
    ) mmcm_i (
        .CLKIN1(sys_clk),
        .RST(reset),
        .PWRDWN(1'b0),
        .CLKFBIN(clkfb),
        .CLKFBOUT(clkfb),
        .CLKFBOUTB(),
        .CLKOUT0(pixel_clk_unbuf),
        .CLKOUT0B(),
        .CLKOUT1(bit_clk_unbuf),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .LOCKED(locked)
    );

    BUFG pixel_bufg (.I(pixel_clk_unbuf), .O(pixel_clk));
    BUFG bit_bufg (.I(bit_clk_unbuf), .O(bit_clk));
`endif

endmodule
