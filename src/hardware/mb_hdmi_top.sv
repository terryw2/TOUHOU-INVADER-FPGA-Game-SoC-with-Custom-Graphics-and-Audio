`timescale 1ns/1ps

module mb_hdmi_top (
    input  logic       Clk,
    input  logic       reset_rtl_0,

    input  logic       uart_rtl_0_rxd,
    output logic       uart_rtl_0_txd,

    input  logic [0:0] gpio_usb_int_tri_i,
    output logic       gpio_usb_rst_tri_o,
    output logic       usb_spi_ss,
    output logic       usb_spi_sclk,
    output logic       usb_spi_mosi,
    input  logic       usb_spi_miso,

    output logic [12:0] ddr3_addr,
    output logic [2:0]  ddr3_ba,
    output logic        ddr3_cas_n,
    output logic [0:0]  ddr3_ck_n,
    output logic [0:0]  ddr3_ck_p,
    output logic [0:0]  ddr3_cke,
    output logic [1:0]  ddr3_dm,
    inout  wire  [15:0] ddr3_dq,
    inout  wire  [1:0]  ddr3_dqs_n,
    inout  wire  [1:0]  ddr3_dqs_p,
    output logic [0:0]  ddr3_odt,
    output logic        ddr3_ras_n,
    output logic        ddr3_reset_n,
    output logic        ddr3_we_n,

    output logic       hdmi_tmds_clk_p,
    output logic       hdmi_tmds_clk_n,
    output logic [2:0] hdmi_tmds_data_p,
    output logic [2:0] hdmi_tmds_data_n,

    output logic       spkl,
    output logic       spkr
);

    logic pixel_clk;
    logic bit_clk;
    logic clk_locked;
    logic video_rst;
    logic bd_reset;

    logic [3:0] vga_r;
    logic [3:0] vga_g;
    logic [3:0] vga_b;
    logic       vga_hsync;
    logic       vga_vsync;
    logic       vga_de;
    logic signed [15:0] audio_pcm_l;
    logic signed [15:0] audio_pcm_r;

    hdmi_clocking clocking_i (
        .sys_clk(Clk),
        .reset(reset_rtl_0),
        .pixel_clk(pixel_clk),
        .bit_clk(bit_clk),
        .locked(clk_locked)
    );

    assign video_rst = reset_rtl_0 || !clk_locked;
    assign bd_reset = reset_rtl_0 || !clk_locked;

`ifdef SIM_STANDALONE
    hdmi_text_controller_v1_0 hdmi_text_i (
        .s_axi_aclk(Clk),
        .s_axi_aresetn(!bd_reset),
        .s_axi_awaddr('0),
        .s_axi_awprot('0),
        .s_axi_awvalid(1'b0),
        .s_axi_awready(),
        .s_axi_wdata('0),
        .s_axi_wstrb('0),
        .s_axi_wvalid(1'b0),
        .s_axi_wready(),
        .s_axi_bresp(),
        .s_axi_bvalid(),
        .s_axi_bready(1'b0),
        .s_axi_araddr('0),
        .s_axi_arprot('0),
        .s_axi_arvalid(1'b0),
        .s_axi_arready(),
        .s_axi_rdata(),
        .s_axi_rresp(),
        .s_axi_rvalid(),
        .s_axi_rready(1'b0),
        .pixel_clk(pixel_clk),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),
        .vga_de(vga_de)
    );

    assign gpio_usb_rst_tri_o = !bd_reset;
    assign usb_spi_ss = 1'b1;
    assign usb_spi_sclk = 1'b0;
    assign usb_spi_mosi = 1'b0;
    assign uart_rtl_0_txd = 1'b1;
    assign ddr3_addr = '0;
    assign ddr3_ba = '0;
    assign ddr3_cas_n = 1'b1;
    assign ddr3_ck_n = 1'b1;
    assign ddr3_ck_p = 1'b0;
    assign ddr3_cke = '0;
    assign ddr3_dm = '0;
    assign ddr3_dq = 'z;
    assign ddr3_dqs_n = 'z;
    assign ddr3_dqs_p = 'z;
    assign ddr3_odt = '0;
    assign ddr3_ras_n = 1'b1;
    assign ddr3_reset_n = 1'b0;
    assign ddr3_we_n = 1'b1;
    assign spkl = 1'b0;
    assign spkr = 1'b0;
    assign audio_pcm_l = 16'sd0;
    assign audio_pcm_r = 16'sd0;
`else
    mb_system_wrapper mb_system_i (
        .Clk(Clk),
        .ddr3_addr(ddr3_addr),
        .ddr3_ba(ddr3_ba),
        .ddr3_cas_n(ddr3_cas_n),
        .ddr3_ck_n(ddr3_ck_n),
        .ddr3_ck_p(ddr3_ck_p),
        .ddr3_cke(ddr3_cke),
        .ddr3_dm(ddr3_dm),
        .ddr3_dq(ddr3_dq),
        .ddr3_dqs_n(ddr3_dqs_n),
        .ddr3_dqs_p(ddr3_dqs_p),
        .ddr3_odt(ddr3_odt),
        .ddr3_ras_n(ddr3_ras_n),
        .ddr3_reset_n(ddr3_reset_n),
        .ddr3_we_n(ddr3_we_n),
        .reset_rtl_0(bd_reset),
        .pixel_clk(pixel_clk),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),
        .vga_de(vga_de),
        .gpio_usb_int_tri_i(gpio_usb_int_tri_i),
        .gpio_usb_rst_tri_o(gpio_usb_rst_tri_o),
        .uart_rtl_0_rxd(uart_rtl_0_rxd),
        .uart_rtl_0_txd(uart_rtl_0_txd),
        .audio_pcm_l(audio_pcm_l),
        .audio_pcm_r(audio_pcm_r),
        .spkl(spkl),
        .spkr(spkr),
        .usb_spi_mosi(usb_spi_mosi),
        .usb_spi_miso(usb_spi_miso),
        .usb_spi_sclk(usb_spi_sclk),
        .usb_spi_ss(usb_spi_ss)
    );
`endif

    hdmi_tmds_tx #(
        .H_ACTIVE(640),
        .H_FRONT_PORCH(16),
        .H_SYNC_PULSE(96),
        .H_BACK_PORCH(48),
        .V_ACTIVE(480),
        .V_FRONT_PORCH(10),
        .V_SYNC_PULSE(2),
        .V_BACK_PORCH(33),
        .VIDEO_ID_CODE(1),
        .VIDEO_RATE_HZ(25_200_000),
        .ENABLE_HDMI_AUDIO(1'b0)
    ) tmds_i (
        .pixel_clk(pixel_clk),
        .bit_clk(bit_clk),
        .rst(video_rst),
        .red(vga_r),
        .green(vga_g),
        .blue(vga_b),
        .hsync(vga_hsync),
        .vsync(vga_vsync),
        .de(vga_de),
        .audio_sample_l(16'h0000),
        .audio_sample_r(16'h0000),
        .audio_sample_toggle(1'b0),
        .hdmi_tmds_clk_p(hdmi_tmds_clk_p),
        .hdmi_tmds_clk_n(hdmi_tmds_clk_n),
        .hdmi_tmds_data_p(hdmi_tmds_data_p),
        .hdmi_tmds_data_n(hdmi_tmds_data_n)
    );

endmodule
