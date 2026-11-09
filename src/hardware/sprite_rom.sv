module sprite_rom (
    input wire [4:0] sprite_type,
    input wire [3:0] frame,
    input wire [3:0] row,
    input wire [3:0] col,
    output reg [3:0] color
);

    reg [3:0] sprite_data [0:8191];
    
    initial begin
        for (integer i = 0; i < 8192; i = i + 1) begin
            sprite_data[i] = 4'h0;
        end
        for (integer r = 0; r < 16; r = r + 1) begin
            for (integer c = 0; c < 16; c = c + 1) begin
                sprite_data[r * 16 + c] = (r >= 4 && r < 12 && c >= 4 && c < 12) ? 4'h1 : 4'h0;
            end
        end
    end

    wire [12:0] addr = {sprite_type[4:0], frame[3:0], row[3:0]};
    always @(*) begin
        color = sprite_data[addr * 16 + col[3:0]];
    end

endmodule