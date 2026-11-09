module mb_hdmi_top_ddr3 (
    input wire sys_clk,
    input wire sys_rst_n,
    
    input wire ddr_clk_p,
    input wire ddr_clk_n,
    
    output wire [15:0] ddr3_addr,
    output wire [2:0] ddr3_ba,
    output wire ddr3_ck_p,
    output wire ddr3_ck_n,
    output wire ddr3_cke,
    output wire ddr3_cs_n,
    output wire ddr3_ras_n,
    output wire ddr3_cas_n,
    output wire ddr3_we_n,
    output wire [1:0] ddr3_dm,
    inout wire [15:0] ddr3_dq,
    inout wire [1:0] ddr3_dqs_p,
    inout wire [1:0] ddr3_dqs_n,
    output wire ddr3_odt,
    
    output wire [3:0] hdmi_tx_clk_n,
    output wire [3:0] hdmi_tx_clk_p,
    output wire [3:0] hdmi_tx_data_n,
    output wire [3:0] hdmi_tx_data_p,
    
    output wire gpio_usb_rst,
    input wire gpio_usb_int,
    input wire [1:0] gpio_usb_keycode,
    
    output wire spi_ss,
    output wire spi_sclk,
    output wire spi_mosi,
    input wire spi_miso,
    
    output wire audio_pwm
);

    wire pixel_clk;
    wire vga_clk;
    wire hdmi_clk;
    wire ddr_ui_clk;
    wire ddr_ui_rst;
    wire mmcm_locked;
    wire init_calib_complete;
    
    wire [3:0] vga_r;
    wire [3:0] vga_g;
    wire [3:0] vga_b;
    wire vga_hsync;
    wire vga_vsync;
    wire vga_de;
    
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire pixel_valid;
    
    wire [3:0] bg_r;
    wire [3:0] bg_g;
    wire [3:0] bg_b;
    wire bg_valid;
    
    wire [3:0] final_r;
    wire [3:0] final_g;
    wire [3:0] final_b;

    hdmi_text_controller_v1_0 hdmi_text_inst (
        .s_axi_aclk(sys_clk),
        .s_axi_aresetn(sys_rst_n),
        .s_axi_awaddr(6'h00),
        .s_axi_awprot(3'h0),
        .s_axi_awvalid(1'b0),
        .s_axi_awready(),
        .s_axi_wdata(32'h00),
        .s_axi_wstrb(4'h0),
        .s_axi_wvalid(1'b0),
        .s_axi_wready(),
        .s_axi_bresp(),
        .s_axi_bvalid(),
        .s_axi_bready(1'b0),
        .s_axi_araddr(6'h00),
        .s_axi_arprot(3'h0),
        .s_axi_arvalid(1'b0),
        .s_axi_arready(),
        .s_axi_rdata(),
        .s_axi_rresp(),
        .s_axi_rvalid(),
        .s_axi_rready(1'b0),
        .pixel_clk(pixel_clk),
        .vga_clk(vga_clk),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),
        .vga_de(vga_de)
    );
    
    tile_renderer tile_renderer_inst (
        .pixel_clk(pixel_clk),
        .rst(!sys_rst_n),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .pixel_valid(pixel_valid),
        .ddr_read_data(64'h0),
        .ddr_read_valid(1'b0),
        .ddr_read_req(),
        .tile_r(bg_r),
        .tile_g(bg_g),
        .tile_b(bg_b),
        .tile_valid(bg_valid)
    );
    
    assign final_r = bg_valid ? bg_r : vga_r;
    assign final_g = bg_valid ? bg_g : vga_g;
    assign final_b = bg_valid ? bg_b : vga_b;
    
    assign gpio_usb_rst = 1'b0;
    assign spi_ss = 1'b1;
    assign spi_sclk = 1'b0;
    assign spi_mosi = 1'b0;
    
    assign ddr3_addr = 16'h0;
    assign ddr3_ba = 3'h0;
    assign ddr3_ck_p = 1'b0;
    assign ddr3_ck_n = 1'b1;
    assign ddr3_cke = 1'b0;
    assign ddr3_cs_n = 1'b1;
    assign ddr3_ras_n = 1'b1;
    assign ddr3_cas_n = 1'b1;
    assign ddr3_we_n = 1'b1;
    assign ddr3_dm = 2'h0;
    assign ddr3_odt = 1'b0;

endmodule