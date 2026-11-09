module tile_renderer #(
    parameter integer TILE_WIDTH = 32,
    parameter integer TILE_HEIGHT = 32,
    parameter integer MAP_WIDTH = 40,
    parameter integer MAP_HEIGHT = 30,
    parameter integer TILE_INDEX_WIDTH = 10,
    parameter integer NUM_TILE_SETS = 4
) (
    input wire pixel_clk,
    input wire rst,
    
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire pixel_valid,
    
    input wire [31:0] ddr_read_data,
    input wire ddr_read_valid,
    output wire ddr_read_req,
    
    output reg [3:0] tile_r,
    output reg [3:0] tile_g,
    output reg [3:0] tile_b,
    output reg tile_valid
);

    localparam TILE_MEM_SIZE = TILE_INDEX_WIDTH * TILE_WIDTH * TILE_HEIGHT / 8;
    localparam MAP_SIZE = MAP_WIDTH * MAP_HEIGHT;
    
    localparam TILE_32X32 = 2'd0;
    localparam TILE_64X64 = 2'd1;
    
    reg [TILE_INDEX_WIDTH-1:0] tile_index;
    reg [5:0] tile_x;
    reg [5:0] tile_y;
    
    reg [15:0] map_data [0:1023];
    
    reg [7:0] tile_set_id;
    reg [1:0] tile_size;
    
    reg [15:0] current_tile;
    reg [5:0] tile_pixel_x;
    reg [5:0] tile_pixel_y;
    
    reg [10:0] ddr_addr;
    reg ddr_req_pending;
    
    reg [7:0] color_palette [0:255];
    
    initial begin
        color_palette[0] = 8'h00;
        color_palette[1] = 8'hFF;
        color_palette[2] = 8'hF0;
        color_palette[3] = 8'h0F;
    end
    
    wire map_x = pixel_x / TILE_WIDTH;
    wire map_y = pixel_y / TILE_HEIGHT;
    wire [15:0] map_addr = map_y * MAP_WIDTH + map_x;
    
    assign ddr_read_req = pixel_valid && !ddr_req_pending;

    always @(posedge pixel_clk) begin
        if (rst) begin
            tile_r <= 4'h0;
            tile_g <= 4'h0;
            tile_b <= 4'h0;
            tile_valid <= 1'b0;
            ddr_req_pending <= 1'b0;
            tile_set_id <= 0;
            tile_size <= TILE_32X32;
        end else begin
            if (pixel_valid) begin
                tile_x <= pixel_x % TILE_WIDTH;
                tile_y <= pixel_y % TILE_HEIGHT;
                tile_index <= map_data[map_addr][TILE_INDEX_WIDTH-1:0];
                tile_set_id <= map_data[map_addr][15:12];
                tile_size <= map_data[map_addr][13:12];
                
                if (tile_size == TILE_32X32) begin
                    ddr_addr <= {tile_set_id[7:0], tile_index[TILE_INDEX_WIDTH-1:0], tile_y[4:0], tile_x[4:0], 2'b00};
                end else begin
                    ddr_addr <= {tile_set_id[7:0], tile_index[TILE_INDEX_WIDTH-1:0], tile_y[5:0], tile_x[5:0], 2'b00};
                end
            end
            
            if (ddr_read_valid) begin
                current_tile <= ddr_read_data[15:0];
                tile_r <= ddr_read_data[15:12];
                tile_g <= ddr_read_data[11:8];
                tile_b <= ddr_read_data[7:4];
                tile_valid <= pixel_valid;
            end else begin
                tile_valid <= 1'b0;
            end
        end
    end

    task load_map_data;
        input [15:0] addr;
        input [15:0] data;
        begin
            map_data[addr] = data;
        end
    endtask

    task init_demo_map;
        integer i, j;
        begin
            for (j = 0; j < MAP_HEIGHT; j = j + 1) begin
                for (i = 0; i < MAP_WIDTH; i = i + 1) begin
                    if (j < 2 || j >= MAP_HEIGHT - 2) begin
                        load_map_data(j * MAP_WIDTH + i, 16'h0010);
                    end else if (i < 5 || i >= MAP_WIDTH - 5) begin
                        load_map_data(j * MAP_WIDTH + i, 16'h0011);
                    end else if ((j % 8 == 0) && (i % 8 < 4)) begin
                        load_map_data(j * MAP_WIDTH + i, 16'h0012);
                    end else begin
                        load_map_data(j * MAP_WIDTH + i, 16'h0000);
                    end
                end
            end
        end
    endtask

endmodule