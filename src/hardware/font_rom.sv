module font_rom (
    input wire [7:0] char_code,
    input wire [3:0] row,
    output reg [7:0] char_data
);

    reg [7:0] font_data [0:2047];

    initial begin
        for (integer i = 0; i < 2048; i = i + 1) begin
            font_data[i] = 8'h00;
        end
        font_data[0] = 8'b00000000;
        font_data[1] = 8'b00011000;
        font_data[2] = 8'b00111100;
        font_data[3] = 8'b01100110;
        font_data[4] = 8'b11000011;
        font_data[5] = 8'b11000011;
        font_data[6] = 8'b01100110;
        font_data[7] = 8'b00111100;
        font_data[8] = 8'b00011000;
        font_data[9] = 8'b00000000;
        
        font_data[16] = 8'b00011000;
        font_data[17] = 8'b00011000;
        font_data[18] = 8'b00011000;
        font_data[19] = 8'b00011000;
        font_data[20] = 8'b11111111;
        font_data[21] = 8'b00011000;
        font_data[22] = 8'b00011000;
        font_data[23] = 8'b00011000;
        font_data[24] = 8'b00011000;
        font_data[25] = 8'b00000000;

        font_data[32] = 8'b00000000;
        font_data[33] = 8'b00110000;
        font_data[34] = 8'b01111000;
        font_data[35] = 8'b11011000;
        font_data[36] = 8'b00011000;
        font_data[37] = 8'b00011000;
        font_data[38] = 8'b00011000;
        font_data[39] = 8'b00011000;
        font_data[40] = 8'b00000000;
        font_data[41] = 8'b00000000;

        font_data[48] = 8'b00000000;
        font_data[49] = 8'b00111000;
        font_data[50] = 8'b01000100;
        font_data[51] = 8'b10001000;
        font_data[52] = 8'b10001000;
        font_data[53] = 8'b01000100;
        font_data[54] = 8'b00111000;
        font_data[55] = 8'b00000000;
        font_data[56] = 8'b00000000;
        font_data[57] = 8'b00000000;

        font_data[64] = 8'b00000000;
        font_data[65] = 8'b00111000;
        font_data[66] = 8'b01000100;
        font_data[67] = 8'b01000100;
        font_data[68] = 8'b01000100;
        font_data[69] = 8'b01000100;
        font_data[70] = 8'b00111000;
        font_data[71] = 8'b00000000;
        font_data[72] = 8'b00000000;
        font_data[73] = 8'b00000000;
    end

    wire [11:0] addr = {char_code[6:0], row[3:0]};
    always @(*) begin
        char_data = font_data[addr];
    end

endmodule