module ddr3_display_path #(
    parameter integer DDR3_ADDR_WIDTH = 32,
    parameter integer DDR3_DATA_WIDTH = 64
) (
    input wire ddr_clk,
    input wire ddr_rst,
    input wire pixel_clk,
    input wire pixel_rst,
    
    input wire [31:0] frame_buffer_addr,
    input wire frame_read_enable,
    output wire frame_read_ready,
    output wire frame_read_complete,
    
    output wire [DDR3_ADDR_WIDTH-1:0] ddr_araddr,
    output wire [7:0] ddr_arlen,
    output wire ddr_arvalid,
    input wire ddr_arready,
    input wire [DDR3_DATA_WIDTH-1:0] ddr_rdata,
    input wire [1:0] ddr_rresp,
    input wire ddr_rlast,
    input wire ddr_rvalid,
    output wire ddr_rready,
    
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire pixel_valid,
    
    output reg [3:0] bg_r,
    output reg [3:0] bg_g,
    output reg [3:0] bg_b,
    output reg bg_valid
);

    localparam BUFFER_SIZE = 640 * 480 * 2;
    localparam BURST_LENGTH = 16;
    
    reg [31:0] read_addr;
    reg [31:0] bytes_read;
    reg [31:0] pixel_buffer [0:4095];
    
    reg [9:0] pixel_x_d1;
    reg [9:0] pixel_y_d1;
    reg pixel_valid_d1;
    
    reg [15:0] pixel_data;
    reg pixel_data_valid;
    
    reg [10:0] buffer_wr_addr;
    reg [15:0] buffer_wr_data;
    reg buffer_wr_en;
    
    reg [10:0] buffer_rd_addr;
    
    reg [1:0] state;
    localparam IDLE = 2'd0;
    localparam READING = 2'd1;
    localparam DONE = 2'd2;
    
    assign frame_read_ready = (state == IDLE);
    assign frame_read_complete = (state == DONE);
    
    assign ddr_araddr = read_addr;
    assign ddr_arlen = BURST_LENGTH - 1;
    assign ddr_arvalid = (state == IDLE) && frame_read_enable;
    assign ddr_rready = pixel_valid_d1;

    always @(posedge ddr_clk) begin
        if (ddr_rst) begin
            state <= IDLE;
            read_addr <= 32'h0;
            bytes_read <= 32'h0;
            bg_r <= 4'h0;
            bg_g <= 4'h0;
            bg_b <= 4'h0;
            bg_valid <= 1'b0;
            buffer_wr_addr <= 0;
            buffer_wr_en <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (frame_read_enable) begin
                        read_addr <= frame_buffer_addr;
                        bytes_read <= 32'h0;
                        state <= READING;
                    end
                    bg_valid <= 1'b0;
                end
                
                READING: begin
                    if (ddr_arvalid && ddr_arready) begin
                        read_addr <= read_addr + (BURST_LENGTH * 8);
                    end
                    
                    if (ddr_rvalid) begin
                        buffer_wr_data <= ddr_rdata[15:0];
                        buffer_wr_addr <= (bytes_read[10:1]) % 4096;
                        buffer_wr_en <= 1'b1;
                        bytes_read <= bytes_read + 8;
                        
                        if (ddr_rlast) begin
                            state <= DONE;
                            buffer_wr_en <= 1'b0;
                        end
                    end
                end
                
                DONE: begin
                    state <= IDLE;
                    bg_valid <= 1'b0;
                end
            endcase
            
            pixel_x_d1 <= pixel_x;
            pixel_y_d1 <= pixel_y;
            pixel_valid_d1 <= pixel_valid;
        end
    end

    reg [10:0] read_buffer_addr;
    always @(posedge pixel_clk) begin
        if (pixel_rst) begin
            read_buffer_addr <= 0;
            pixel_data_valid <= 1'b0;
            bg_r <= 4'h0;
            bg_g <= 4'h0;
            bg_b <= 4'h0;
            bg_valid <= 1'b0;
        end else begin
            if (pixel_valid && (state == DONE)) begin
                read_buffer_addr <= pixel_y * 32 + (pixel_x / 2);
                pixel_data_valid <= 1'b1;
            end
            
            if (pixel_data_valid) begin
                if (pixel_x[0]) begin
                    bg_r <= pixel_data[11:8];
                    bg_g <= pixel_data[7:4];
                    bg_b <= pixel_data[3:0];
                end else begin
                    bg_r <= pixel_data[15:12];
                    bg_g <= pixel_data[11:8];
                    bg_b <= pixel_data[7:4];
                end
                bg_valid <= pixel_valid;
            end else begin
                bg_r <= 4'h0;
                bg_g <= 4'h0;
                bg_b <= 4'h1;
                bg_valid <= pixel_valid;
            end
        end
    end

endmodule