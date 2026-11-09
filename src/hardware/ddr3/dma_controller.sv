module dma_controller #(
    parameter integer C_S_AXI_ADDR_WIDTH = 32,
    parameter integer C_S_AXI_DATA_WIDTH = 64,
    parameter integer C_S_AXI_ID_WIDTH = 4,
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 64,
    parameter integer C_M_AXI_ID_WIDTH = 4,
    parameter integer C_MAX_BURST_LEN = 256,
    parameter integer C_NUM_AXI_MASTER = 1
) (
    input wire s_axi_aclk,
    input wire s_axi_aresetn,
    input wire [C_S_AXI_ID_WIDTH-1:0] s_axi_awid,
    input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input wire [7:0] s_axi_awlen,
    input wire [2:0] s_axi_awsize,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input wire [7:0] s_axi_wstrb,
    input wire s_axi_wlast,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output wire [C_S_AXI_ID_WIDTH-1:0] s_axi_bid,
    output wire [1:0] s_axi_bresp,
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    
    input wire m_axi_aclk,
    input wire m_axi_aresetn,
    output wire [C_M_AXI_ID_WIDTH-1:0] m_axi_arid,
    output wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    input wire [C_M_AXI_ID_WIDTH-1:0] m_axi_rid,
    input wire [C_M_AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready,
    
    output wire [31:0] ddr_read_addr,
    output wire ddr_read_enable,
    input wire [63:0] ddr_read_data,
    input wire ddr_read_valid,
    output wire ddr_read_ready,
    
    input wire [2:0] cfg_cmd,
    input wire cfg_enable,
    input wire cfg_start,
    output wire cfg_done,
    output wire cfg_idle,
    output wire [31:0] cfg_status
);

    localparam IDLE = 3'd0;
    localparam SETUP = 3'd1;
    localparam READ_ADDR = 3'd2;
    localparam READ_DATA = 3'd3;
    localparam WRITE_DATA = 3'd4;
    localparam COMPLETE = 3'd5;

    reg [2:0] state;
    reg [2:0] next_state;
    
    reg [31:0] src_addr;
    reg [31:0] dst_addr;
    reg [31:0] transfer_size;
    reg [31:0] bytes_transferred;
    
    reg [C_M_AXI_ID_WIDTH-1:0] m_axi_arid_reg;
    reg [C_M_AXI_ADDR_WIDTH-1:0] m_axi_araddr_reg;
    reg [7:0] m_axi_arlen_reg;
    reg [2:0] m_axi_arsize_reg;
    reg [1:0] m_axi_arburst_reg;
    reg m_axi_arvalid_reg;
    reg m_axi_rready_reg;
    
    assign m_axi_arid = m_axi_arid_reg;
    assign m_axi_araddr = m_axi_araddr_reg;
    assign m_axi_arlen = m_axi_arlen_reg;
    assign m_axi_arsize = m_axi_arsize_reg;
    assign m_axi_arburst = m_axi_arburst_reg;
    assign m_axi_arvalid = m_axi_arvalid_reg;
    assign m_axi_rready = m_axi_rready_reg;

    assign s_axi_awready = 1'b0;
    assign s_axi_wready = 1'b0;
    assign s_axi_bid = 0;
    assign s_axi_bresp = 2'b00;
    assign s_axi_bvalid = 1'b0;
    
    assign ddr_read_addr = src_addr + bytes_transferred;
    assign ddr_read_enable = (state == READ_DATA);
    assign ddr_read_ready = (state == READ_DATA) && ddr_read_valid;

    assign cfg_idle = (state == IDLE);
    assign cfg_done = (state == COMPLETE);
    assign cfg_status = bytes_transferred;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (cfg_enable && cfg_start) begin
                    next_state = SETUP;
                end
            end
            SETUP: begin
                next_state = READ_ADDR;
            end
            READ_ADDR: begin
                if (m_axi_arvalid && m_axi_arready) begin
                    next_state = READ_DATA;
                end
            end
            READ_DATA: begin
                if (m_axi_rvalid && m_axi_rlast) begin
                    next_state = COMPLETE;
                end
            end
            COMPLETE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            src_addr <= 32'h0;
            dst_addr <= 32'h0;
            transfer_size <= 32'h0;
            bytes_transferred <= 32'h0;
            m_axi_arid_reg <= 0;
            m_axi_araddr_reg <= 32'h0;
            m_axi_arlen_reg <= 8'h0;
            m_axi_arsize_reg <= 3'h0;
            m_axi_arburst_reg <= 2'h0;
            m_axi_arvalid_reg <= 1'b0;
            m_axi_rready_reg <= 1'b0;
        end else begin
            case (state)
                SETUP: begin
                    case (cfg_cmd)
                        3'd0: src_addr <= 32'h80000000;
                        3'd1: src_addr <= 32'h80010000;
                        3'd2: src_addr <= 32'h80020000;
                        default: src_addr <= 32'h80000000;
                    endcase
                    transfer_size <= 32'h00010000;
                    bytes_transferred <= 32'h0;
                    m_axi_arlen_reg <= 8'hFF;
                    m_axi_arsize_reg <= 3'h3;
                    m_axi_arburst_reg <= 2'h1;
                    m_axi_arid_reg <= 4'h1;
                end
                READ_ADDR: begin
                    m_axi_araddr_reg <= src_addr + bytes_transferred;
                    m_axi_arvalid_reg <= 1'b1;
                    m_axi_rready_reg <= 1'b1;
                end
                READ_DATA: begin
                    if (m_axi_rvalid) begin
                        bytes_transferred <= bytes_transferred + 8;
                    end
                    if (m_axi_rvalid && m_axi_rlast) begin
                        m_axi_arvalid_reg <= 1'b0;
                        m_axi_rready_reg <= 1'b0;
                    end
                end
            endcase
        end
    end

endmodule