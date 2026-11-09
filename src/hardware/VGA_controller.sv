`timescale 1ns/1ps

module vga_controller #(
    parameter int H_ACTIVE = 640,
    parameter int H_FRONT_PORCH = 16,
    parameter int H_SYNC_PULSE = 96,
    parameter int H_BACK_PORCH = 48,
    parameter int V_ACTIVE = 480,
    parameter int V_FRONT_PORCH = 10,
    parameter int V_SYNC_PULSE = 2,
    parameter int V_BACK_PORCH = 33
) (
    input  logic        clk,
    input  logic        rst,
    output logic        hsync,
    output logic        vsync,
    output logic        de,
    output logic [10:0] pixel_x,
    output logic [10:0] pixel_y,
    output logic        pixel_valid,
    output logic        frame_start
);

    localparam int H_TOTAL = H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH;
    localparam int V_TOTAL = V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH;

    logic [$clog2(H_TOTAL)-1:0] h_count;
    logic [$clog2(V_TOTAL)-1:0] v_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            h_count <= '0;
            v_count <= '0;
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= '0;
            if (v_count == V_TOTAL - 1) begin
                v_count <= '0;
            end else begin
                v_count <= v_count + 1'b1;
            end
        end else begin
            h_count <= h_count + 1'b1;
        end
    end

    always_comb begin
        pixel_x = (h_count < H_ACTIVE) ? 11'(h_count) : 11'(H_ACTIVE - 1);
        pixel_y = (v_count < V_ACTIVE) ? 11'(v_count) : 11'(V_ACTIVE - 1);
        de = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
        pixel_valid = de;

        // 640x480 @ 60 Hz uses negative polarity syncs.
        hsync = ~((h_count >= H_ACTIVE + H_FRONT_PORCH) &&
                  (h_count <  H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE));
        vsync = ~((v_count >= V_ACTIVE + V_FRONT_PORCH) &&
                  (v_count <  V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE));
        frame_start = (h_count == H_ACTIVE - 1) && (v_count == V_ACTIVE - 1);
    end

endmodule
