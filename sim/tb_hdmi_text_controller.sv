`timescale 1ns/1ps

module tb_hdmi_text_controller;

    localparam int CONTROL_ADDR = 10'h1F0;
    localparam int FRAME_ADDR = 10'h1F4;
    localparam int TEXT0_ADDR = 10'h080;
    localparam int TEXT0_POS_ADDR = 10'h100;

    logic axi_clk = 1'b0;
    logic pixel_clk = 1'b0;
    logic rst_n = 1'b0;

    logic [9:0] awaddr;
    logic [2:0] awprot;
    logic awvalid;
    logic awready;
    logic [31:0] wdata;
    logic [3:0] wstrb;
    logic wvalid;
    logic wready;
    logic [1:0] bresp;
    logic bvalid;
    logic bready;
    logic [9:0] araddr;
    logic [2:0] arprot;
    logic arvalid;
    logic arready;
    logic [31:0] rdata;
    logic [1:0] rresp;
    logic rvalid;
    logic rready;

    logic [3:0] r;
    logic [3:0] g;
    logic [3:0] b;
    logic hsync;
    logic vsync;
    logic de;

    always #5 axi_clk = ~axi_clk;
    always #20 pixel_clk = ~pixel_clk;

    hdmi_text_controller_v1_0 dut (
        .s_axi_aclk(axi_clk),
        .s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr),
        .s_axi_awprot(awprot),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),
        .s_axi_bready(bready),
        .s_axi_araddr(araddr),
        .s_axi_arprot(arprot),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        .pixel_clk(pixel_clk),
        .vga_r(r),
        .vga_g(g),
        .vga_b(b),
        .vga_hsync(hsync),
        .vga_vsync(vsync),
        .vga_de(de)
    );

    task automatic axi_write(input logic [9:0] addr, input logic [31:0] data);
        begin
            @(posedge axi_clk);
            awaddr <= addr;
            wdata <= data;
            wstrb <= 4'hF;
            awvalid <= 1'b1;
            wvalid <= 1'b1;
            bready <= 1'b1;
            wait (awready && wready);
            @(posedge axi_clk);
            awvalid <= 1'b0;
            wvalid <= 1'b0;
            wait (bvalid);
            if (bresp != 2'b00) begin
                $fatal(1, "AXI write response error at %03h", addr);
            end
            @(posedge axi_clk);
            bready <= 1'b0;
        end
    endtask

    task automatic axi_read(input logic [9:0] addr, output logic [31:0] data);
        begin
            @(posedge axi_clk);
            araddr <= addr;
            arvalid <= 1'b1;
            rready <= 1'b1;
            wait (arready);
            @(posedge axi_clk);
            arvalid <= 1'b0;
            wait (rvalid);
            data = rdata;
            if (rresp != 2'b00) begin
                $fatal(1, "AXI read response error at %03h", addr);
            end
            @(posedge axi_clk);
            rready <= 1'b0;
        end
    endtask

    task automatic wait_pixel(input int x, input int y);
        begin
            wait (de && dut.pixel_x == x && dut.pixel_y == y);
            @(posedge pixel_clk);
            #1;
        end
    endtask

    initial begin
        logic [31:0] read_value;
        logic [31:0] sprite_word;
        logic [31:0] text_pos;

        awaddr = '0;
        awprot = '0;
        awvalid = 1'b0;
        wdata = '0;
        wstrb = '0;
        wvalid = 1'b0;
        bready = 1'b0;
        araddr = '0;
        arprot = '0;
        arvalid = 1'b0;
        rready = 1'b0;

        repeat (8) @(posedge axi_clk);
        rst_n = 1'b1;
        repeat (8) @(posedge axi_clk);

        wait_pixel(10, 10);
        if ({r, g, b} != 12'hFFF) begin
            $fatal(1, "Expected power-up colorbar white at (10,10), got %03h", {r, g, b});
        end

        axi_write(CONTROL_ADDR, 32'h00000001);
        sprite_word = (32'h1 << 31) | (32'd32 << 10) | 32'd32;
        axi_write(10'h000, sprite_word);

        wait_pixel(40, 42);
        if ({r, g, b} == 12'h000) begin
            $fatal(1, "Expected visible player sprite pixel, got black");
        end

        axi_write(TEXT0_ADDR, 32'h524F4353);
        axi_write(TEXT0_ADDR + 10'h004, 32'h00000045);
        text_pos = (32'hF << 28) | (32'h1 << 27) | (32'd5 << 20) | (32'd10 << 10) | 32'd20;
        axi_write(TEXT0_POS_ADDR, text_pos);

        wait_pixel(21, 12);
        if ({r, g, b} != 12'hFFF) begin
            $fatal(1, "Expected white SCORE text pixel, got %03h", {r, g, b});
        end

        wait (dut.frame_counter_pix >= 32'd1);
        axi_read(FRAME_ADDR, read_value);
        if (read_value == 32'h0) begin
            $fatal(1, "Expected frame counter to increment");
        end

        $display("tb_hdmi_text_controller PASS");
        $finish;
    end

endmodule
