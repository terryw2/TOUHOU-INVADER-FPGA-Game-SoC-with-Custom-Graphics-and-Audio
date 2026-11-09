module ddr3_controller #(
    parameter integer C_S_AXI_ADDR_WIDTH = 32,
    parameter integer C_S_AXI_DATA_WIDTH = 64,
    parameter integer C_S_AXI_ID_WIDTH = 4,
    parameter integer C_S_AXI_AWUSER_WIDTH = 4,
    parameter integer C_S_AXI_ARUSER_WIDTH = 4,
    parameter integer C_S_AXI_WUSER_WIDTH = 0,
    parameter integer C_S_AXI_RUSER_WIDTH = 0,
    parameter integer C_S_AXI_BUSER_WIDTH = 0,
    parameter integer C_MEMORY_WIDTH = 16,
    parameter integer C_MEMORY_ADDR_WIDTH = 27,
    parameter integer C_MEMORY_BANKADDR_WIDTH = 3,
    parameter integer C_MEMORY_ROW_WIDTH = 15,
    parameter integer C_MEMORY_COL_WIDTH = 10,
    parameter integer C_MEM_ADDR_ORDER = "ROW_BANK_COLUMN",
    parameter integer C_OUTPUT_TIME = "OUTPUT_DELAYED",
    parameter integer integer C_USE_AXI = 1,
    parameter integer C_USE_HBM = 0,
    parameter integer C_USE_DATA_VALID = 0,
    parameter integer C_XDEV = "VIRTEX7"
) (
    input wire c0_sys_clk_p,
    input wire c0_sys_clk_n,
    input wire c0_sys_rst,
    output wire [C_MEMORY_ADDR_WIDTH-1:0] c0_ddr3_addr,
    output wire [C_MEMORY_BANKADDR_WIDTH-1:0] c0_ddr3_ba,
    output wire c0_ddr3_ck_p,
    output wire c0_ddr3_ck_n,
    output wire c0_ddr3_cke,
    output wire c0_ddr3_cs_n,
    output wire c0_ddr3_ras_n,
    output wire c0_ddr3_cas_n,
    output wire c0_ddr3_we_n,
    output wire [C_MEMORY_WIDTH/16-1:0] c0_ddr3_dm,
    inout wire [C_MEMORY_WIDTH-1:0] c0_ddr3_dq,
    inout wire [C_MEMORY_WIDTH/8-1:0] c0_ddr3_dqs_p,
    inout wire [C_MEMORY_WIDTH/8-1:0] c0_ddr3_dqs_n,
    output wire c0_ddr3_odt,
    
    input wire s_axi_aclk,
    input wire s_axi_aresetn,
    input wire [C_S_AXI_ID_WIDTH-1:0] s_axi_awid,
    input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input wire [7:0] s_axi_awlen,
    input wire [2:0] s_axi_awsize,
    input wire [1:0] s_axi_awburst,
    input wire [C_S_AXI_AWUSER_WIDTH-1:0] s_axi_awuser,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input wire s_axi_wlast,
    input wire [C_S_AXI_WUSER_WIDTH-1:0] s_axi_wuser,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output wire [C_S_AXI_ID_WIDTH-1:0] s_axi_bid,
    output wire [1:0] s_axi_bresp,
    output wire [C_S_AXI_BUSER_WIDTH-1:0] s_axi_buser,
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    input wire [C_S_AXI_ID_WIDTH-1:0] s_axi_arid,
    input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input wire [7:0] s_axi_arlen,
    input wire [2:0] s_axi_arsize,
    input wire [1:0] s_axi_arburst,
    input wire [C_S_AXI_ARUSER_WIDTH-1:0] s_axi_aruser,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output wire [C_S_AXI_ID_WIDTH-1:0] s_axi_rid,
    output wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output wire s_axi_rlast,
    output wire [C_S_AXI_RUSER_WIDTH-1:0] s_axi_ruser,
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    
    output wire ui_clk,
    output wire ui_clk_sync_rst,
    output wire mmcm_locked,
    output wire init_calib_complete
);

    wire [C_S_AXI_ID_WIDTH-1:0] m_axi_awid;
    wire [C_S_AXI_ADDR_WIDTH-1:0] m_axi_awaddr;
    wire [7:0] m_axi_awlen;
    wire [2:0] m_axi_awsize;
    wire [1:0] m_axi_awburst;
    wire [3:0] m_axi_awvalid;
    wire [3:0] m_axi_awready;
    wire [C_S_AXI_DATA_WIDTH-1:1] m_axi_wdata;
    wire [7:0] m_axi_wstrb;
    wire m_axi_wlast;
    wire m_axi_wvalid;
    wire m_axi_wready;
    wire [3:0] m_axi_bid;
    wire [7:0] m_axi_bresp;
    wire [3:0] m_axi_bvalid;
    wire m_axi_bready;
    wire [3:0] m_axi_arid;
    wire [C_S_AXI_DATA_WIDTH-1:1] m_axi_araddr;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire [3:0] m_axi_arvalid;
    wire [3:0] m_axi_arready;
    wire [3:0] m_axi_rid;
    wire [C_S_AXI_DATA_WIDTH-1:1] m_axi_rdata;
    wire [7:0] m_axi_rresp;
    wire [3:0] m_axi_rlast;
    wire [3:0] m_axi_rvalid;
    wire m_axi_rready;

    wire app_sr_active;
    wire app_ref_ack;
    wire app_zq_ack;
    wire [11:0] device_temp;

    assign m_axi_awid = s_axi_awid;
    assign m_axi_awaddr = {s_axi_awaddr[31:3], 3'b000};
    assign m_axi_awlen = s_axi_awlen;
    assign m_axi_awsize = s_axi_awsize;
    assign m_axi_awburst = s_axi_awburst;
    assign m_axi_awvalid = {4{s_axi_awvalid}};
    assign s_axi_awready = m_axi_awready[0];
    
    assign m_axi_wdata = s_axi_wdata[C_S_AXI_DATA_WIDTH-1:1];
    assign m_axi_wstrb = s_axi_wstrb[7:1];
    assign m_axi_wlast = s_axi_wlast;
    assign m_axi_wvalid = s_axi_wvalid;
    assign s_axi_wready = m_axi_wready[0];
    
    assign s_axi_bid = m_axi_bid[0];
    assign s_axi_bresp = m_axi_bresp[1:0];
    assign s_axi_buser = 0;
    assign s_axi_bvalid = m_axi_bvalid[0];
    assign m_axi_bready = s_axi_bready;
    
    assign m_axi_arid = s_axi_arid;
    assign m_axi_araddr = {s_axi_araddr[31:3], 3'b000};
    assign m_axi_arlen = s_axi_arlen;
    assign m_axi_arsize = s_axi_arsize;
    assign m_axi_arburst = s_axi_arburst;
    assign m_axi_arvalid = {4{s_axi_arvalid}};
    assign s_axi_arready = m_axi_arready[0];
    
    assign s_axi_rid = m_axi_rid[0];
    assign s_axi_rdata = {32'h0, m_axi_rdata[C_S_AXI_DATA_WIDTH-1:1]};
    assign s_axi_rresp = m_axi_rresp[1:0];
    assign s_axi_rlast = m_axi_rlast[0];
    assign s_axi_ruser = 0;
    assign s_axi_rvalid = m_axi_rvalid[0];
    assign m_axi_rready = s_axi_rready;

    mig_7series_0 u_mig (
        .c0_sys_clk_p(c0_sys_clk_p),
        .c0_sys_clk_n(c0_sys_clk_n),
        .c0_sys_rst(c0_sys_rst),
        .c0_ddr3_addr(c0_ddr3_addr),
        .c0_ddr3_ba(c0_ddr3_ba),
        .c0_ddr3_ck_p(c0_ddr3_ck_p),
        .c0_ddr3_ck_n(c0_ddr3_ck_n),
        .c0_ddr3_cke(c0_ddr3_cke),
        .c0_ddr3_cs_n(c0_ddr3_cs_n),
        .c0_ddr3_ras_n(c0_ddr3_ras_n),
        .c0_ddr3_cas_n(c0_ddr3_cas_n),
        .c0_ddr3_we_n(c0_ddr3_we_n),
        .c0_ddr3_dm(c0_ddr3_dm),
        .c0_ddr3_dq(c0_ddr3_dq),
        .c0_ddr3_dqs_p(c0_ddr3_dqs_p),
        .c0_ddr3_dqs_n(c0_ddr3_dqs_n),
        .c0_ddr3_odt(c0_ddr3_odt),
        
        .migm_aclk(ui_clk),
        .migm_aresetn(~ui_clk_sync_rst),
        
        .m_axi_awid(m_axi_awid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        
        .m_axi_arid(m_axi_arid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        
        .s_axi_aclk(s_axi_aclk),
        .s_axi_aresetn(s_axi_aresetn),
        
        .app_sr_active(app_sr_active),
        .app_ref_ack(app_ref_ack),
        .app_zq_ack(app_zq_ack),
        
        .init_calib_complete(init_calib_complete),
        .device_temp(device_temp),
        
        .mmcm_locked(mmcm_locked)
    );

endmodule