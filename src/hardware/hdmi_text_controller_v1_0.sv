`timescale 1ns/1ps

module hdmi_text_controller_v1_0 #(
    parameter int C_S_AXI_ADDR_WIDTH = 16,
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int H_ACTIVE = 640,
    parameter int H_FRONT_PORCH = 16,
    parameter int H_SYNC_PULSE = 96,
    parameter int H_BACK_PORCH = 48,
    parameter int V_ACTIVE = 480,
    parameter int V_FRONT_PORCH = 10,
    parameter int V_SYNC_PULSE = 2,
    parameter int V_BACK_PORCH = 33
) (
    input  logic                              s_axi_aclk,
    input  logic                              s_axi_aresetn,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  logic [2:0]                        s_axi_awprot,
    input  logic                              s_axi_awvalid,
    output logic                              s_axi_awready,
    input  logic [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  logic                              s_axi_wvalid,
    output logic                              s_axi_wready,
    output logic [1:0]                        s_axi_bresp,
    output logic                              s_axi_bvalid,
    input  logic                              s_axi_bready,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  logic [2:0]                        s_axi_arprot,
    input  logic                              s_axi_arvalid,
    output logic                              s_axi_arready,
    output logic [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output logic [1:0]                        s_axi_rresp,
    output logic                              s_axi_rvalid,
    input  logic                              s_axi_rready,

    input  logic                              pixel_clk,
    output logic [3:0]                        vga_r,
    output logic [3:0]                        vga_g,
    output logic [3:0]                        vga_b,
    output logic                              vga_hsync,
    output logic                              vga_vsync,
    output logic                              vga_de
);

    localparam int REG_WORDS = 256;
    localparam int SPRITE_COUNT = 96;
    localparam int TEXT_LINES = 16;
    localparam int SPRITE_WORD_BASE = 0;
    localparam int TEXT_WORD_BASE = 96;
    localparam int TEXT_POS_BASE = 160;
    localparam int SHIELD_WORD_BASE = 176;
    localparam int AUDIO_CONTROL_WORD = 248;
    localparam int CONTROL_WORD = 252;
    localparam int FRAME_COUNTER_WORD = 253;
    localparam int DRAW_X_WORD = 254;
    localparam int DRAW_Y_WORD = 255;
    localparam int BG_TILE_WORD_BASE = 256;
    localparam int BG_TILE_WORDS = 256;
    localparam int BG_PALETTE_WORD_BASE = 512;
    localparam int BG_PALETTE_WORDS = 4;
    localparam int BG_CHR_WORD_BASE = 528;
    localparam int BG_CHR_WORDS = 512;
    localparam int ATLAS_WORD_BASE = 1040;
    localparam int ATLAS_FRAME_COUNT = 44;
    localparam int ATLAS_WORDS = ATLAS_FRAME_COUNT * 32 * 32 / 8;
    localparam int BG_TILE_WORD_BITS = $clog2(BG_TILE_WORDS);
    localparam int BG_CHR_WORD_BITS = $clog2(BG_CHR_WORDS);
    localparam int ATLAS_WORD_BITS = $clog2(ATLAS_WORDS);
    logic [31:0] reg_array [0:REG_WORDS-1];
    logic [31:0] bg_palette_words [0:BG_PALETTE_WORDS-1];

    logic [C_S_AXI_ADDR_WIDTH-1:0] awaddr_latched;
    logic [C_S_AXI_DATA_WIDTH-1:0] wdata_latched;
    logic [(C_S_AXI_DATA_WIDTH/8)-1:0] wstrb_latched;
    logic have_aw;
    logic have_w;

    wire [C_S_AXI_ADDR_WIDTH-3:0] aw_word = awaddr_latched[C_S_AXI_ADDR_WIDTH-1:2];
    wire [C_S_AXI_ADDR_WIDTH-3:0] ar_word = s_axi_araddr[C_S_AXI_ADDR_WIDTH-1:2];
    wire write_ready = have_aw && have_w && !s_axi_bvalid;
    wire bg_tile_write_ready = write_ready &&
                               (aw_word >= BG_TILE_WORD_BASE) &&
                               (aw_word < (BG_TILE_WORD_BASE + BG_TILE_WORDS));
    wire bg_chr_write_ready = write_ready &&
                              (aw_word >= BG_CHR_WORD_BASE) &&
                              (aw_word < (BG_CHR_WORD_BASE + BG_CHR_WORDS));
    wire [BG_TILE_WORD_BITS-1:0] bg_tile_aw_index = BG_TILE_WORD_BITS'(aw_word - BG_TILE_WORD_BASE);
    wire [BG_CHR_WORD_BITS-1:0] bg_chr_aw_index = BG_CHR_WORD_BITS'(aw_word - BG_CHR_WORD_BASE);
    wire atlas_write_ready = write_ready &&
                             (aw_word >= ATLAS_WORD_BASE) &&
                             (aw_word < (ATLAS_WORD_BASE + ATLAS_WORDS));
    wire [ATLAS_WORD_BITS-1:0] atlas_aw_index = ATLAS_WORD_BITS'(aw_word - ATLAS_WORD_BASE);

    logic [10:0] pixel_x;
    logic [10:0] pixel_y;
    logic pixel_valid;
    logic frame_start;
    logic [31:0] frame_counter_pix;
    logic [31:0] frame_counter_meta;
    logic [31:0] frame_counter_axi;
    logic [10:0] draw_x_meta;
    logic [10:0] draw_x_axi;
    logic [10:0] draw_y_meta;
    logic [10:0] draw_y_axi;
    logic [11:0] stage0_base_rgb;
    logic [11:0] stage0_text_rgb;
    logic        stage0_text_hit;
    logic        stage0_sprite_hit;
    logic        stage0_sprite_asset;
    logic [2:0]  stage0_sprite_tint;
    logic [3:0]  stage0_proc_sprite_sample;
    logic [ATLAS_WORD_BITS-1:0] stage0_atlas_word;
    logic [2:0]  stage0_atlas_nibble;
    logic        stage0_force_black;
    logic        stage0_force_colorbar;
    logic [10:0] stage0_bg_x;
    logic [10:0] stage0_bg_y;
    logic [10:0] stage0_bg_scroll_y;
    logic [31:0] bg_tile_pixel_word;
    logic [31:0] bg_chr_pixel_word;
    logic [BG_TILE_WORD_BITS-1:0] bg_tile_pixel_addr;
    logic [BG_CHR_WORD_BITS-1:0] bg_chr_pixel_addr;
    logic [31:0] atlas_pixel_word;
    logic [11:0] stage1_base_rgb;
    logic [11:0] stage1_text_rgb;
    logic        stage1_text_hit;
    logic        stage1_sprite_hit;
    logic        stage1_sprite_asset;
    logic [2:0]  stage1_sprite_tint;
    logic [3:0]  stage1_proc_sprite_sample;
    logic [2:0]  stage1_atlas_nibble;
    logic [3:0]  stage1_asset_sprite_sample;
    logic [3:0]  stage1_sprite_sample;
    logic        stage1_force_black;
    logic        stage1_force_colorbar;
    logic [10:0] stage1_bg_x;
    logic [10:0] stage1_bg_y;
    logic [10:0] stage1_bg_scroll_y;
    logic [7:0]  stage1_bg_tile_id;
    logic [2:0]  stage1_bg_chr_row;
    logic [2:0]  stage1_bg_chr_col;
    logic [11:0] stage2_base_rgb;
    logic [11:0] stage2_text_rgb;
    logic        stage2_text_hit;
    logic        stage2_sprite_hit;
    logic [2:0]  stage2_sprite_tint;
    logic [3:0]  stage2_sprite_sample;
    logic        stage2_force_black;
    logic        stage2_force_colorbar;
    logic [10:0] stage2_bg_x;
    logic [10:0] stage2_bg_y;
    logic [10:0] stage2_bg_scroll_y;
    logic [7:0]  stage2_bg_tile_id;
    logic [2:0]  stage2_bg_chr_col;

    function automatic logic [31:0] apply_wstrb(
        input logic [31:0] old_value,
        input logic [31:0] new_value,
        input logic [3:0]  strobe
    );
        logic [31:0] merged;
        begin
            merged = old_value;
            for (int i = 0; i < 4; i++) begin
                if (strobe[i]) begin
                    merged[i*8 +: 8] = new_value[i*8 +: 8];
                end
            end
            apply_wstrb = merged;
        end
    endfunction

`ifdef SIM_USE_BEHAVIORAL_ATLAS
    (* ram_style = "block" *) logic [31:0] bg_tile_words [0:BG_TILE_WORDS-1];
    (* ram_style = "block" *) logic [31:0] bg_chr_words [0:BG_CHR_WORDS-1];

    always_ff @(posedge s_axi_aclk) begin
        if (bg_tile_write_ready) begin
            bg_tile_words[bg_tile_aw_index] <= apply_wstrb(bg_tile_words[bg_tile_aw_index],
                                                           wdata_latched, wstrb_latched);
        end
        if (bg_chr_write_ready) begin
            bg_chr_words[bg_chr_aw_index] <= apply_wstrb(bg_chr_words[bg_chr_aw_index],
                                                         wdata_latched, wstrb_latched);
        end
    end

    always_ff @(posedge pixel_clk) begin
        bg_tile_pixel_word <= bg_tile_words[bg_tile_pixel_addr];
        bg_chr_pixel_word <= bg_chr_words[bg_chr_pixel_addr];
    end
`else
    xpm_memory_tdpram #(
        .ADDR_WIDTH_A(BG_TILE_WORD_BITS),
        .ADDR_WIDTH_B(BG_TILE_WORD_BITS),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(8),
        .BYTE_WRITE_WIDTH_B(8),
        .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("independent_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(BG_TILE_WORDS * 32),
        .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_A(32),
        .READ_DATA_WIDTH_B(32),
        .READ_LATENCY_A(1),
        .READ_LATENCY_B(1),
        .READ_RESET_VALUE_A("0"),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .SIM_ASSERT_CHK(0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(0),
        .USE_MEM_INIT_MMI(0),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(32),
        .WRITE_DATA_WIDTH_B(32),
        .WRITE_MODE_A("read_first"),
        .WRITE_MODE_B("read_first")
    ) bg_tile_ram_i (
        .sleep(1'b0),
        .clka(s_axi_aclk),
        .rsta(!s_axi_aresetn),
        .ena(1'b1),
        .regcea(1'b1),
        .wea(bg_tile_write_ready ? wstrb_latched : 4'b0000),
        .addra(bg_tile_aw_index),
        .dina(wdata_latched),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .douta(),
        .sbiterra(),
        .dbiterra(),
        .clkb(pixel_clk),
        .rstb(!s_axi_aresetn),
        .enb(1'b1),
        .regceb(1'b1),
        .web(4'b0000),
        .addrb(bg_tile_pixel_addr),
        .dinb(32'h0),
        .injectsbiterrb(1'b0),
        .injectdbiterrb(1'b0),
        .doutb(bg_tile_pixel_word),
        .sbiterrb(),
        .dbiterrb()
    );

    xpm_memory_tdpram #(
        .ADDR_WIDTH_A(BG_CHR_WORD_BITS),
        .ADDR_WIDTH_B(BG_CHR_WORD_BITS),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(8),
        .BYTE_WRITE_WIDTH_B(8),
        .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("independent_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(BG_CHR_WORDS * 32),
        .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_A(32),
        .READ_DATA_WIDTH_B(32),
        .READ_LATENCY_A(1),
        .READ_LATENCY_B(1),
        .READ_RESET_VALUE_A("0"),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .SIM_ASSERT_CHK(0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(0),
        .USE_MEM_INIT_MMI(0),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(32),
        .WRITE_DATA_WIDTH_B(32),
        .WRITE_MODE_A("read_first"),
        .WRITE_MODE_B("read_first")
    ) bg_chr_ram_i (
        .sleep(1'b0),
        .clka(s_axi_aclk),
        .rsta(!s_axi_aresetn),
        .ena(1'b1),
        .regcea(1'b1),
        .wea(bg_chr_write_ready ? wstrb_latched : 4'b0000),
        .addra(bg_chr_aw_index),
        .dina(wdata_latched),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .douta(),
        .sbiterra(),
        .dbiterra(),
        .clkb(pixel_clk),
        .rstb(!s_axi_aresetn),
        .enb(1'b1),
        .regceb(1'b1),
        .web(4'b0000),
        .addrb(bg_chr_pixel_addr),
        .dinb(32'h0),
        .injectsbiterrb(1'b0),
        .injectdbiterrb(1'b0),
        .doutb(bg_chr_pixel_word),
        .sbiterrb(),
        .dbiterrb()
    );
`endif

`ifdef SIM_USE_BEHAVIORAL_ATLAS
    (* ram_style = "block" *) logic [31:0] sprite_atlas_words [0:ATLAS_WORDS-1];

    always_ff @(posedge s_axi_aclk) begin
        if (atlas_write_ready) begin
            sprite_atlas_words[atlas_aw_index] <= wdata_latched;
        end
    end

    always_ff @(posedge pixel_clk) begin
        atlas_pixel_word <= sprite_atlas_words[stage0_atlas_word];
    end
`else
    xpm_memory_tdpram #(
        .ADDR_WIDTH_A(ATLAS_WORD_BITS),
        .ADDR_WIDTH_B(ATLAS_WORD_BITS),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(32),
        .BYTE_WRITE_WIDTH_B(32),
        .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("independent_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(ATLAS_WORDS * 32),
        .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_A(32),
        .READ_DATA_WIDTH_B(32),
        .READ_LATENCY_A(1),
        .READ_LATENCY_B(1),
        .READ_RESET_VALUE_A("0"),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .SIM_ASSERT_CHK(0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(0),
        .USE_MEM_INIT_MMI(0),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(32),
        .WRITE_DATA_WIDTH_B(32),
        .WRITE_MODE_A("read_first"),
        .WRITE_MODE_B("read_first")
    ) sprite_atlas_ram_i (
        .sleep(1'b0),
        .clka(s_axi_aclk),
        .rsta(!s_axi_aresetn),
        .ena(1'b1),
        .regcea(1'b1),
        .wea({4{atlas_write_ready}}),
        .addra(atlas_aw_index),
        .dina(wdata_latched),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .douta(),
        .sbiterra(),
        .dbiterra(),
        .clkb(pixel_clk),
        .rstb(!s_axi_aresetn),
        .enb(1'b1),
        .regceb(1'b1),
        .web(4'b0000),
        .addrb(stage0_atlas_word),
        .dinb(32'h0),
        .injectsbiterrb(1'b0),
        .injectdbiterrb(1'b0),
        .doutb(atlas_pixel_word),
        .sbiterrb(),
        .dbiterrb()
    );
`endif

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_arready <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= 32'h0;
            s_axi_rresp <= 2'b00;
            awaddr_latched <= '0;
            wdata_latched <= '0;
            wstrb_latched <= '0;
            have_aw <= 1'b0;
            have_w <= 1'b0;
            for (int i = 0; i < REG_WORDS; i++) begin
                reg_array[i] <= 32'h0;
            end
            bg_palette_words[0] <= 32'h0000_0012;
            bg_palette_words[1] <= 32'h0000_0123;
            bg_palette_words[2] <= 32'h0000_0233;
            bg_palette_words[3] <= 32'h0000_0456;
            reg_array[CONTROL_WORD] <= 32'h1;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_arready <= 1'b0;

            if (!have_aw && s_axi_awvalid) begin
                awaddr_latched <= s_axi_awaddr;
                have_aw <= 1'b1;
                s_axi_awready <= 1'b1;
            end

            if (!have_w && s_axi_wvalid) begin
                wdata_latched <= s_axi_wdata;
                wstrb_latched <= s_axi_wstrb;
                have_w <= 1'b1;
                s_axi_wready <= 1'b1;
            end

            if (write_ready) begin
                if (aw_word < FRAME_COUNTER_WORD) begin
                    reg_array[aw_word[7:0]] <= apply_wstrb(reg_array[aw_word[7:0]], wdata_latched, wstrb_latched);
                end else if ((aw_word >= BG_TILE_WORD_BASE) && (aw_word < (BG_TILE_WORD_BASE + BG_TILE_WORDS))) begin
                    // The background tilemap is written by the XPM block RAM port above.
                end else if ((aw_word >= BG_PALETTE_WORD_BASE) && (aw_word < (BG_PALETTE_WORD_BASE + BG_PALETTE_WORDS))) begin
                    bg_palette_words[aw_word - BG_PALETTE_WORD_BASE] <= apply_wstrb(bg_palette_words[aw_word - BG_PALETTE_WORD_BASE],
                                                                                    wdata_latched, wstrb_latched);
                end else if ((aw_word >= BG_CHR_WORD_BASE) && (aw_word < (BG_CHR_WORD_BASE + BG_CHR_WORDS))) begin
                    // The background CHR rows are written by the XPM block RAM port above.
                end else if ((aw_word >= ATLAS_WORD_BASE) && (aw_word < (ATLAS_WORD_BASE + ATLAS_WORDS))) begin
                    // The atlas is written by the XPM block RAM port above; software uses full-word writes.
                end
                have_aw <= 1'b0;
                have_w <= 1'b0;
                s_axi_bresp <= 2'b00;
                s_axi_bvalid <= 1'b1;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (!s_axi_rvalid && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                unique case (ar_word)
                    FRAME_COUNTER_WORD: s_axi_rdata <= frame_counter_axi;
                    DRAW_X_WORD:        s_axi_rdata <= {21'h0, draw_x_axi};
                    DRAW_Y_WORD:        s_axi_rdata <= {21'h0, draw_y_axi};
                    default: begin
                        if (ar_word < REG_WORDS) begin
                            s_axi_rdata <= reg_array[ar_word[7:0]];
                        end else if ((ar_word >= BG_TILE_WORD_BASE) && (ar_word < (BG_TILE_WORD_BASE + BG_TILE_WORDS))) begin
                            s_axi_rdata <= 32'h0;
                        end else if ((ar_word >= BG_PALETTE_WORD_BASE) && (ar_word < (BG_PALETTE_WORD_BASE + BG_PALETTE_WORDS))) begin
                            s_axi_rdata <= bg_palette_words[ar_word - BG_PALETTE_WORD_BASE];
                        end else if ((ar_word >= BG_CHR_WORD_BASE) && (ar_word < (BG_CHR_WORD_BASE + BG_CHR_WORDS))) begin
                            s_axi_rdata <= 32'h0;
                        end else begin
                            s_axi_rdata <= 32'h0;
                        end
                    end
                endcase
                s_axi_rresp <= 2'b00;
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    vga_controller #(
        .H_ACTIVE(H_ACTIVE),
        .H_FRONT_PORCH(H_FRONT_PORCH),
        .H_SYNC_PULSE(H_SYNC_PULSE),
        .H_BACK_PORCH(H_BACK_PORCH),
        .V_ACTIVE(V_ACTIVE),
        .V_FRONT_PORCH(V_FRONT_PORCH),
        .V_SYNC_PULSE(V_SYNC_PULSE),
        .V_BACK_PORCH(V_BACK_PORCH)
    ) timing_i (
        .clk(pixel_clk),
        .rst(!s_axi_aresetn),
        .hsync(vga_hsync),
        .vsync(vga_vsync),
        .de(vga_de),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .pixel_valid(pixel_valid),
        .frame_start(frame_start)
    );

    always_ff @(posedge pixel_clk) begin
        if (!s_axi_aresetn) begin
            frame_counter_pix <= 32'h0;
        end else if (frame_start) begin
            frame_counter_pix <= frame_counter_pix + 1'b1;
        end
    end

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            frame_counter_meta <= 32'h0;
            frame_counter_axi <= 32'h0;
            draw_x_meta <= 11'h0;
            draw_x_axi <= 11'h0;
            draw_y_meta <= 11'h0;
            draw_y_axi <= 11'h0;
        end else begin
            frame_counter_meta <= frame_counter_pix;
            frame_counter_axi <= frame_counter_meta;
            draw_x_meta <= pixel_x;
            draw_x_axi <= draw_x_meta;
            draw_y_meta <= pixel_y;
            draw_y_axi <= draw_y_meta;
        end
    end

    // A small tint field lets software flash damage, recolor bullets, and vary enemies.
    function automatic logic [11:0] palette(input logic [3:0] color_id, input logic [2:0] tint);
        logic [11:0] color;
        begin
            unique case (color_id)
                4'h0: color = 12'h000;
                4'h1: color = 12'h0CF;
                4'h2: color = 12'h0F4;
                4'h3: color = 12'hF43;
                4'h4: color = 12'hFC0;
                4'h5: color = 12'hF0F;
                4'h6: color = 12'hFFF;
                4'h7: color = 12'h112;
                4'h8: color = 12'hF8A;
                4'h9: color = 12'h8FF;
                4'hA: color = 12'h8F8;
                4'hB: color = 12'h36C;
                4'hC: color = 12'hAA0;
                4'hD: color = 12'h99A;
                4'hE: color = 12'hA0A;
                4'hF: color = 12'hFFF;
                default: color = 12'hDDD;
            endcase

            unique case (tint)
                3'd1: color = {color[11:8], color[7:4] >> 1, color[3:0] >> 1};
                3'd2: color = {color[11:8] >> 1, color[7:4], color[3:0] >> 1};
                3'd3: color = {color[11:8] >> 1, color[7:4] >> 1, color[3:0]};
                3'd4: color = color | 12'h333;
                default: color = color;
            endcase
            palette = color;
        end
    endfunction

    function automatic logic [11:0] colorbar(input logic [10:0] x);
        begin
            unique case (x / 80)
                0: colorbar = 12'hFFF;
                1: colorbar = 12'hFF0;
                2: colorbar = 12'h0FF;
                3: colorbar = 12'h0F0;
                4: colorbar = 12'hF0F;
                5: colorbar = 12'hF00;
                6: colorbar = 12'h00F;
                default: colorbar = 12'h000;
            endcase
        end
    endfunction

    function automatic logic [BG_TILE_WORD_BITS-1:0] bg_tilemap_word_addr(input logic [6:0] tile_x, input logic [6:0] tile_y);
        logic [9:0] tile_index;
        begin
            tile_index = {tile_y[4:0], tile_x[4:0]};
            bg_tilemap_word_addr = BG_TILE_WORD_BITS'(tile_index[9:2]);
        end
    endfunction

    function automatic logic [7:0] bg_tilemap_sample_from_word(
        input logic [31:0] tile_word,
        input logic [6:0] tile_x,
        input logic [6:0] tile_y
    );
        logic [9:0] tile_index;
        logic [4:0] shift;
        begin
            tile_index = {tile_y[4:0], tile_x[4:0]};
            shift = {tile_index[1:0], 3'b000};
            bg_tilemap_sample_from_word = (tile_word >> shift) & 8'hFF;
        end
    endfunction

    function automatic logic [1:0] pic_bg_chr_pixel_from_word(
        input logic [15:0] row_bits,
        input logic [2:0] col
    );
        logic [3:0] shift;
        begin
            shift = {(3'd7 - col), 1'b0};
            pic_bg_chr_pixel_from_word = (row_bits >> shift) & 2'b11;
        end
    endfunction

    function automatic logic [11:0] pic_bg_palette(
        input logic [1:0] px,
        input logic [7:0] tile,
        input logic [10:0] x,
        input logic [10:0] y
    );
        logic [11:0] c0;
        logic [11:0] c1;
        logic [11:0] c2;
        logic [11:0] c3;
        begin
            c0 = bg_palette_words[0][11:0];
            c1 = bg_palette_words[1][11:0];
            c2 = bg_palette_words[2][11:0];
            c3 = bg_palette_words[3][11:0];
            unique case (px)
                2'd0: pic_bg_palette = c0;
                2'd1: pic_bg_palette = c1;
                2'd2: pic_bg_palette = tile[3] ? (c2 | 12'h111) : c2;
                default: pic_bg_palette = tile[2] ? (c3 | 12'h111) : c3;
            endcase
        end
    endfunction

    function automatic logic [7:0] panel_bg_tile(
        input logic [6:0] tile_x,
        input logic [6:0] tile_y
    );
        logic [1:0] panel_pick;
        begin
            panel_pick = tile_x[1:0] + tile_y[1:0];
            unique case (panel_pick)
                2'd0: panel_bg_tile = 8'd0;
                2'd1: panel_bg_tile = 8'd1;
                2'd2: panel_bg_tile = 8'd12;
                default: panel_bg_tile = 8'd13;
            endcase
        end
    endfunction

    // Replace this compact 8x8 table to change the game's typeface; the renderer adds the neon shadow.
    function automatic logic [7:0] font_bits(input logic [7:0] char_code, input logic [2:0] row);
        begin
            unique case (char_code)
                "0": case (row) 0: font_bits = 8'h3C; 1: font_bits = 8'h66; 2: font_bits = 8'h6E; 3: font_bits = 8'h76; 4: font_bits = 8'h66; 5: font_bits = 8'h66; 6: font_bits = 8'h3C; default: font_bits = 8'h00; endcase
                "1": case (row) 0: font_bits = 8'h18; 1: font_bits = 8'h38; 2: font_bits = 8'h18; 3: font_bits = 8'h18; 4: font_bits = 8'h18; 5: font_bits = 8'h18; 6: font_bits = 8'h7E; default: font_bits = 8'h00; endcase
                "2": case (row) 0: font_bits = 8'h3C; 1: font_bits = 8'h66; 2: font_bits = 8'h06; 3: font_bits = 8'h1C; 4: font_bits = 8'h30; 5: font_bits = 8'h60; 6: font_bits = 8'h7E; default: font_bits = 8'h00; endcase
                "3": case (row) 0: font_bits = 8'h3C; 1: font_bits = 8'h66; 2: font_bits = 8'h06; 3: font_bits = 8'h1C; 4: font_bits = 8'h06; 5: font_bits = 8'h66; 6: font_bits = 8'h3C; default: font_bits = 8'h00; endcase
                "4": case (row) 0: font_bits = 8'h0C; 1: font_bits = 8'h1C; 2: font_bits = 8'h3C; 3: font_bits = 8'h6C; 4: font_bits = 8'h7E; 5: font_bits = 8'h0C; 6: font_bits = 8'h0C; default: font_bits = 8'h00; endcase
                "5": case (row) 0: font_bits = 8'h7E; 1: font_bits = 8'h60; 2: font_bits = 8'h7C; 3: font_bits = 8'h06; 4: font_bits = 8'h06; 5: font_bits = 8'h66; 6: font_bits = 8'h3C; default: font_bits = 8'h00; endcase
                "6": case (row) 0: font_bits = 8'h1C; 1: font_bits = 8'h30; 2: font_bits = 8'h60; 3: font_bits = 8'h7C; 4: font_bits = 8'h66; 5: font_bits = 8'h66; 6: font_bits = 8'h3C; default: font_bits = 8'h00; endcase
                "7": case (row) 0: font_bits = 8'h7E; 1: font_bits = 8'h06; 2: font_bits = 8'h0C; 3: font_bits = 8'h18; 4: font_bits = 8'h30; 5: font_bits = 8'h30; 6: font_bits = 8'h30; default: font_bits = 8'h00; endcase
                "8": case (row) 0: font_bits = 8'h3C; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h3C; 4: font_bits = 8'h66; 5: font_bits = 8'h66; 6: font_bits = 8'h3C; default: font_bits = 8'h00; endcase
                "9": case (row) 0: font_bits = 8'h3C; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h3E; 4: font_bits = 8'h06; 5: font_bits = 8'h0C; 6: font_bits = 8'h38; default: font_bits = 8'h00; endcase
                "A": case (row) 0: font_bits = 8'h18; 1: font_bits = 8'h3C; 2: font_bits = 8'h66; 3: font_bits = 8'h66; 4: font_bits = 8'h7E; 5: font_bits = 8'h66; 6: font_bits = 8'h66; default: font_bits = 8'h00; endcase
                "B": case (row) 0: font_bits = 8'h7C; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h7C; 4: font_bits = 8'h66; 5: font_bits = 8'h66; 6: font_bits = 8'h7C; default: font_bits = 8'h00; endcase
                "C": case (row) 0: font_bits = 8'h3C; 1: font_bits = 8'h66; 2: font_bits = 8'h60; 3: font_bits = 8'h60; 4: font_bits = 8'h60; 5: font_bits = 8'h66; 6: font_bits = 8'h3C; default: font_bits = 8'h00; endcase
                "D": case (row) 0: font_bits = 8'h7C; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h66; 4: font_bits = 8'h66; 5: font_bits = 8'h66; 6: font_bits = 8'h7C; default: font_bits = 8'h00; endcase
                "E": case (row) 0: font_bits = 8'h7E; 1: font_bits = 8'h60; 2: font_bits = 8'h60; 3: font_bits = 8'h7C; 4: font_bits = 8'h60; 5: font_bits = 8'h60; 6: font_bits = 8'h7E; default: font_bits = 8'h00; endcase
                "F": case (row) 0: font_bits = 8'h7E; 1: font_bits = 8'h60; 2: font_bits = 8'h60; 3: font_bits = 8'h7C; 4: font_bits = 8'h60; 5: font_bits = 8'h60; 6: font_bits = 8'h60; default: font_bits = 8'h00; endcase
                "G": case (row) 0: font_bits = 8'h3C; 1: font_bits = 8'h66; 2: font_bits = 8'h60; 3: font_bits = 8'h6E; 4: font_bits = 8'h66; 5: font_bits = 8'h66; 6: font_bits = 8'h3E; default: font_bits = 8'h00; endcase
                "H": case (row) 0: font_bits = 8'h66; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h7E; 4: font_bits = 8'h66; 5: font_bits = 8'h66; 6: font_bits = 8'h66; default: font_bits = 8'h00; endcase
                "I": case (row) 0: font_bits = 8'h3C; 1: font_bits = 8'h18; 2: font_bits = 8'h18; 3: font_bits = 8'h18; 4: font_bits = 8'h18; 5: font_bits = 8'h18; 6: font_bits = 8'h3C; default: font_bits = 8'h00; endcase
                "K": case (row) 0: font_bits = 8'h66; 1: font_bits = 8'h6C; 2: font_bits = 8'h78; 3: font_bits = 8'h70; 4: font_bits = 8'h78; 5: font_bits = 8'h6C; 6: font_bits = 8'h66; default: font_bits = 8'h00; endcase
                "L": case (row) 0: font_bits = 8'h60; 1: font_bits = 8'h60; 2: font_bits = 8'h60; 3: font_bits = 8'h60; 4: font_bits = 8'h60; 5: font_bits = 8'h60; 6: font_bits = 8'h7E; default: font_bits = 8'h00; endcase
                "M": case (row) 0: font_bits = 8'h63; 1: font_bits = 8'h77; 2: font_bits = 8'h7F; 3: font_bits = 8'h6B; 4: font_bits = 8'h63; 5: font_bits = 8'h63; 6: font_bits = 8'h63; default: font_bits = 8'h00; endcase
                "N": case (row) 0: font_bits = 8'h66; 1: font_bits = 8'h76; 2: font_bits = 8'h7E; 3: font_bits = 8'h7E; 4: font_bits = 8'h6E; 5: font_bits = 8'h66; 6: font_bits = 8'h66; default: font_bits = 8'h00; endcase
                "O": case (row) 0: font_bits = 8'h3C; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h66; 4: font_bits = 8'h66; 5: font_bits = 8'h66; 6: font_bits = 8'h3C; default: font_bits = 8'h00; endcase
                "P": case (row) 0: font_bits = 8'h7C; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h7C; 4: font_bits = 8'h60; 5: font_bits = 8'h60; 6: font_bits = 8'h60; default: font_bits = 8'h00; endcase
                "R": case (row) 0: font_bits = 8'h7C; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h7C; 4: font_bits = 8'h6C; 5: font_bits = 8'h66; 6: font_bits = 8'h66; default: font_bits = 8'h00; endcase
                "S": case (row) 0: font_bits = 8'h3E; 1: font_bits = 8'h60; 2: font_bits = 8'h60; 3: font_bits = 8'h3C; 4: font_bits = 8'h06; 5: font_bits = 8'h06; 6: font_bits = 8'h7C; default: font_bits = 8'h00; endcase
                "T": case (row) 0: font_bits = 8'h7E; 1: font_bits = 8'h18; 2: font_bits = 8'h18; 3: font_bits = 8'h18; 4: font_bits = 8'h18; 5: font_bits = 8'h18; 6: font_bits = 8'h18; default: font_bits = 8'h00; endcase
                "U": case (row) 0: font_bits = 8'h66; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h66; 4: font_bits = 8'h66; 5: font_bits = 8'h66; 6: font_bits = 8'h3C; default: font_bits = 8'h00; endcase
                "V": case (row) 0: font_bits = 8'h66; 1: font_bits = 8'h66; 2: font_bits = 8'h66; 3: font_bits = 8'h66; 4: font_bits = 8'h66; 5: font_bits = 8'h3C; 6: font_bits = 8'h18; default: font_bits = 8'h00; endcase
                "W": case (row) 0: font_bits = 8'h63; 1: font_bits = 8'h63; 2: font_bits = 8'h63; 3: font_bits = 8'h6B; 4: font_bits = 8'h7F; 5: font_bits = 8'h77; 6: font_bits = 8'h63; default: font_bits = 8'h00; endcase
                "X": case (row) 0: font_bits = 8'h66; 1: font_bits = 8'h66; 2: font_bits = 8'h3C; 3: font_bits = 8'h18; 4: font_bits = 8'h3C; 5: font_bits = 8'h66; 6: font_bits = 8'h66; default: font_bits = 8'h00; endcase
                "Y": case (row) 0: font_bits = 8'h66; 1: font_bits = 8'h66; 2: font_bits = 8'h3C; 3: font_bits = 8'h18; 4: font_bits = 8'h18; 5: font_bits = 8'h18; 6: font_bits = 8'h18; default: font_bits = 8'h00; endcase
                "Z": case (row) 0: font_bits = 8'h7E; 1: font_bits = 8'h06; 2: font_bits = 8'h0C; 3: font_bits = 8'h18; 4: font_bits = 8'h30; 5: font_bits = 8'h60; 6: font_bits = 8'h7E; default: font_bits = 8'h00; endcase
                ":": case (row) 1: font_bits = 8'h18; 2: font_bits = 8'h18; 4: font_bits = 8'h18; 5: font_bits = 8'h18; default: font_bits = 8'h00; endcase
                "/": case (row) 0: font_bits = 8'h06; 1: font_bits = 8'h0C; 2: font_bits = 8'h0C; 3: font_bits = 8'h18; 4: font_bits = 8'h30; 5: font_bits = 8'h30; 6: font_bits = 8'h60; default: font_bits = 8'h00; endcase
                "!": case (row) 0: font_bits = 8'h18; 1: font_bits = 8'h18; 2: font_bits = 8'h18; 3: font_bits = 8'h18; 4: font_bits = 8'h18; 6: font_bits = 8'h18; default: font_bits = 8'h00; endcase
                " ": font_bits = 8'h00;
                default: case (row) 0: font_bits = 8'h7E; 1: font_bits = 8'h42; 2: font_bits = 8'h0C; 3: font_bits = 8'h18; 4: font_bits = 8'h00; 5: font_bits = 8'h18; 6: font_bits = 8'h18; default: font_bits = 8'h00; endcase
            endcase
        end
    endfunction

    function automatic logic font_sample(
        input logic [7:0] char_code,
        input logic [2:0] row,
        input logic [2:0] col
    );
        logic [7:0] bits;
        begin
            bits = font_bits(char_code, row);
            font_sample = bits[3'd7 - col];
        end
    endfunction

    // Procedural 16x16 sprites, hand-compressed from the added pixel-art PNG assets.
    function automatic logic [3:0] frame_mod7(input logic [3:0] frame);
        begin
            frame_mod7 = (frame < 4'd7) ? frame :
                         ((frame < 4'd14) ? (frame - 4'd7) : (frame - 4'd14));
        end
    endfunction

    function automatic logic [2:0] frame_mod5(input logic [3:0] frame);
        begin
            frame_mod5 = (frame < 4'd5) ? frame[2:0] :
                         ((frame < 4'd10) ? (frame - 4'd5) : (frame - 4'd10));
        end
    endfunction

    function automatic logic [2:0] frame_mod6(input logic [3:0] frame);
        begin
            frame_mod6 = (frame < 4'd6) ? frame[2:0] :
                         ((frame < 4'd12) ? (frame - 4'd6) : (frame - 4'd12));
        end
    endfunction

    function automatic logic [5:0] atlas_frame_index(
        input logic [4:0] sprite_type,
        input logic [3:0] frame
    );
        begin
            unique case (sprite_type)
                5'd6:  atlas_frame_index = 6'd28 + {5'b00000, frame[0]};
                5'd7:  atlas_frame_index = 6'd30;
                5'd8:  atlas_frame_index = 6'd27;
                5'd4:  atlas_frame_index = 6'd36;
                5'd5:  atlas_frame_index = 6'd37;
                5'd9:  atlas_frame_index = {2'b00, frame_mod7(frame)};
                5'd10: atlas_frame_index = 6'd8 + {3'b000, frame_mod5(frame)};
                5'd11: atlas_frame_index = 6'd16 + {3'b000, frame_mod6(frame)};
                5'd12: atlas_frame_index = 6'd22 + {3'b000, frame_mod5(frame)};
                5'd13: atlas_frame_index = 6'd31;
                5'd17: atlas_frame_index = 6'd38;
                5'd18: atlas_frame_index = 6'd39;
                5'd19: atlas_frame_index = 6'd36;
                5'd20: atlas_frame_index = 6'd30;
                5'd21: atlas_frame_index = 6'd32;
                5'd22: atlas_frame_index = 6'd33;
                5'd23: atlas_frame_index = 6'd34;
                5'd24: atlas_frame_index = 6'd35;
                5'd25: atlas_frame_index = {2'b00, frame_mod7(frame)};
                default: atlas_frame_index = 6'h3F;
            endcase
        end
    endfunction

    function automatic logic [5:0] runtime_atlas_frame_index(
        input logic [4:0] sprite_type,
        input logic [3:0] frame,
        input logic [5:0] row,
        input logic [5:0] col
    );
        begin
            if ((sprite_type >= 5'd14) && (sprite_type <= 5'd16)) begin
                runtime_atlas_frame_index = 6'd40 + {4'b0000, row[5], col[5]};
            end else begin
                runtime_atlas_frame_index = atlas_frame_index(sprite_type, frame);
            end
        end
    endfunction

    function automatic logic [3:0] sprite_pixel(
        input logic [4:0] sprite_type,
        input logic [3:0] frame,
        input logic [5:0] row,
        input logic [5:0] col
    );
        logic body;
        logic [6:0] sum_rc;
        logic [6:0] dist_x;
        logic [6:0] dist_y;
        logic [6:0] manhattan;
        begin
            sprite_pixel = 4'h0;
            sum_rc = {1'b0, row} + {1'b0, col};
            dist_x = (col > 6'd31) ? {1'b0, (col - 6'd31)} : {1'b0, (6'd31 - col)};
            dist_y = (row > 6'd31) ? {1'b0, (row - 6'd31)} : {1'b0, (6'd31 - row)};
            manhattan = dist_x + dist_y;
            unique case (sprite_type)
                5'd0: begin
                    if (((row == 4'd0) && (col == 4'd7 || col == 4'd8)) ||
                        ((row == 4'd1) && (col == 4'd7 || col == 4'd8))) begin
                        sprite_pixel = 4'h6;
                    end else if ((row >= 4'd2) && (row <= 4'd5) &&
                                 (col >= (4'd7 - row[1:0])) && (col <= (4'd8 + row[1:0]))) begin
                        sprite_pixel = (row == 4'd2) ? 4'h6 : 4'h3;
                    end else if (((row >= 4'd5) && (row <= 4'd8) && (col >= 4'd3) && (col <= 4'd12)) ||
                                 ((row == 4'd9) && (col >= 4'd1) && (col <= 4'd14))) begin
                        sprite_pixel = ((row == 4'd5) || (col == 4'd3) || (col == 4'd12)) ? 4'h6 : 4'h4;
                    end else if ((row >= 4'd10) && (row <= 4'd12) && (col >= 4'd0) && (col <= 4'd15)) begin
                        sprite_pixel = (col <= 4'd2 || col >= 4'd13) ? 4'h3 : 4'h4;
                    end else if ((row == 4'd13) && (col >= 4'd4) && (col <= 4'd11)) begin
                        sprite_pixel = 4'h3;
                    end else if ((row >= 4'd14) && (col >= 4'd6) && (col <= 4'd9)) begin
                        sprite_pixel = frame[0] ? 4'h4 : 4'h8;
                    end
                end
                5'd1: begin
                    if (((col <= 4'd4) && (row >= 4'd3) && (row <= 4'd10) && (col + row >= 4'd6) && (row >= col)) ||
                        ((col >= 4'd11) && (row >= 4'd5) && (row <= 4'd13) && (col + row <= 5'd24))) begin
                        sprite_pixel = 4'h6;
                    end else if ((row >= 4'd5) && (row <= 4'd11) && (col >= 4'd5) && (col <= 4'd10)) begin
                        sprite_pixel = ((row == 4'd7 || row == 4'd8) && (col >= 4'd7) && (col <= 4'd8)) ? 4'h3 : 4'h6;
                    end else if ((row >= 4'd7) && (row <= 4'd10) && (col >= 4'd6) && (col <= 4'd9)) begin
                        sprite_pixel = 4'h3;
                    end else if (frame[0] && (row == 4'd12) && (col >= 4'd6) && (col <= 4'd9)) begin
                        sprite_pixel = 4'h4;
                    end
                end
                5'd2: begin
                    if (((row >= 4'd2) && (row <= 4'd13) && (col >= 4'd4) && (col <= 4'd11) &&
                         ((row == 4'd2) || (row == 4'd13) || (col == 4'd4) || (col == 4'd11))) ||
                        ((row >= 4'd4) && (row <= 4'd11) && (col >= 4'd2) && (col <= 4'd13) &&
                         ((row == 4'd4) || (row == 4'd11) || (col == 4'd2) || (col == 4'd13)))) begin
                        sprite_pixel = 4'h6;
                    end else if ((row >= 4'd5) && (row <= 4'd10) && (col >= 4'd5) && (col <= 4'd10)) begin
                        sprite_pixel = ((row >= 4'd7) && (row <= 4'd8) && (col >= 4'd7) && (col <= 4'd8)) ? 4'h6 : 4'h3;
                    end else if (frame[0] && ((row == 4'd1) || (row == 4'd14)) && (col >= 4'd7) && (col <= 4'd8)) begin
                        sprite_pixel = 4'h4;
                    end
                end
                5'd3: begin
                    body = ((row >= 4'd4) && (row <= 4'd11) && (col >= 4'd3) && (col <= 4'd12)) ||
                           ((row >= 4'd6) && (row <= 4'd9) && (col >= 4'd1) && (col <= 4'd14));
                    if (body) begin
                        sprite_pixel = ((row == 4'd6 || row == 4'd9) && (col >= 4'd6) && (col <= 4'd9)) ? 4'h8 : 4'h5;
                    end
                    if ((row == 4'd7 || row == 4'd8) && (col >= 4'd7) && (col <= 4'd8)) begin
                        sprite_pixel = 4'h6;
                    end
                end
                5'd4: begin
                    if ((row >= 4'd1) && (row <= 4'd13) && (col >= 4'd6) && (col <= 4'd9)) begin
                        sprite_pixel = ((col == 4'd7 || col == 4'd8) && row < 4'd10) ? 4'h6 : 4'h4;
                    end else if ((row >= 4'd10) && (row <= 4'd14) && (col >= 4'd5) && (col <= 4'd10)) begin
                        sprite_pixel = frame[0] ? 4'h8 : 4'h4;
                    end
                end
                5'd5: begin
                    if ((row >= 4'd2) && (row <= 4'd12) && (col >= 4'd6) && (col <= 4'd9)) begin
                        sprite_pixel = ((row >= 4'd4) && (row <= 4'd9) && (col >= 4'd7) && (col <= 4'd8)) ? 4'h4 : 4'h3;
                    end else if ((row >= 4'd11) && (row <= 4'd14) && (col >= 4'd5) && (col <= 4'd10)) begin
                        sprite_pixel = 4'h8;
                    end
                end
                5'd6: begin
                    body = (row == col) || (row + col == 4'd15) ||
                           ((row >= 4'd5) && (row <= 4'd10) && (col >= 4'd5) && (col <= 4'd10)) ||
                           ((row == 4'd7 || row == 4'd8) || (col == 4'd7 || col == 4'd8));
                    if (body) begin
                        sprite_pixel = (frame[1]) ? 4'h3 : ((frame[0]) ? 4'h4 : 4'h6);
                    end
                end
                5'd7: begin
                    if (((row >= 4'd2) && (row <= 4'd13) && (col >= 4'd7) && (col <= 4'd8)) ||
                        ((col >= 4'd2) && (col <= 4'd13) && (row >= 4'd7) && (row <= 4'd8))) begin
                        sprite_pixel = 4'hA;
                    end
                    if ((row >= 4'd6) && (row <= 4'd9) && (col >= 4'd6) && (col <= 4'd9)) begin
                        sprite_pixel = 4'h6;
                    end
                end
                5'd8: begin
                    if ((row >= 4'd0) && (row <= 4'd15) && (col >= 4'd7) && (col <= 4'd8)) begin
                        sprite_pixel = (row[1]) ? 4'h9 : 4'h6;
                    end
                    if ((row == 4'd0 || row == 4'd15) && (col >= 4'd5) && (col <= 4'd10)) begin
                        sprite_pixel = 4'h9;
                    end
                end
                5'd9: begin
                    dist_x = (col > 6'd15) ? {1'b0, (col - 6'd15)} : {1'b0, (6'd15 - col)};
                    if ((row >= 6'd1) && (row <= 6'd5) && (col >= 6'd9) && (col <= 6'd22) &&
                        ((row <= 6'd2) || (col == 6'd9) || (col == 6'd10) || (col == 6'd21) || (col == 6'd22))) begin
                        sprite_pixel = 4'h6;
                    end else if ((row >= 6'd4) && (row <= 6'd11) && (dist_x <= 7'd5)) begin
                        sprite_pixel = (row <= 6'd8) ? 4'h4 : 4'h6;
                    end else if ((row >= 6'd8) && (row <= 6'd14) && (dist_x <= 7'd4)) begin
                        sprite_pixel = 4'h8;
                    end else if ((row >= 6'd13) && (row <= 6'd23) && (dist_x <= ({1'b0, row} - 7'd9))) begin
                        sprite_pixel = (row[1] ^ col[1] ^ frame[1]) ? 4'h3 : 4'h8;
                    end else if ((row >= 6'd12) && (row <= 6'd21) &&
                                 (((col >= 6'd3) && (col <= 6'd9)) || ((col >= 6'd22) && (col <= 6'd28)))) begin
                        sprite_pixel = (row[0] ^ frame[0]) ? 4'h6 : 4'h8;
                    end else if ((row >= 6'd20) && (row <= 6'd27) &&
                                 (((col >= 6'd10) && (col <= 6'd14)) || ((col >= 6'd17) && (col <= 6'd21)))) begin
                        sprite_pixel = (row <= 6'd23) ? 4'h6 : 4'h3;
                    end else if ((row >= 6'd27) && (col >= 6'd12) && (col <= 6'd19)) begin
                        sprite_pixel = frame[0] ? 4'hF : 4'h4;
                    end
                    if ((row >= 6'd14) && (row <= 6'd16) && (col >= 6'd14) && (col <= 6'd17)) begin
                        sprite_pixel = 4'h6;
                    end
                end
                5'd10: begin
                    dist_x = (col > 6'd15) ? {1'b0, (col - 6'd15)} : {1'b0, (6'd15 - col)};
                    if ((row >= 6'd5) && (row <= 6'd14) &&
                        (((col >= 6'd3) && (col <= 6'd10)) || ((col >= 6'd21) && (col <= 6'd28)))) begin
                        sprite_pixel = (row[1] ^ col[1] ^ frame[1]) ? 4'h9 : 4'h6;
                    end
                    if ((row >= 6'd4) && (row <= 6'd10) && (dist_x <= 7'd4)) begin
                        sprite_pixel = 4'h4;
                    end
                    if ((row >= 6'd10) && (row <= 6'd22) && (dist_x <= ({1'b0, row} - 7'd7))) begin
                        sprite_pixel = frame[0] ? 4'h5 : 4'h8;
                    end
                    if ((row >= 6'd20) && (row <= 6'd28) && (col >= 6'd12) && (col <= 6'd19)) begin
                        sprite_pixel = 4'h6;
                    end
                end
                5'd11: begin
                    dist_x = (col > 6'd15) ? {1'b0, (col - 6'd15)} : {1'b0, (6'd15 - col)};
                    dist_y = (row > 6'd15) ? {1'b0, (row - 6'd15)} : {1'b0, (6'd15 - row)};
                    manhattan = dist_x + dist_y;
                    if ((manhattan >= 6'd10) && (manhattan <= 6'd17)) begin
                        sprite_pixel = 4'h6;
                    end else if ((manhattan < 6'd10) && (dist_x <= 6'd11) && (dist_y <= 6'd11)) begin
                        sprite_pixel = (dist_x + dist_y < 6'd5) ? 4'h9 : 4'h3;
                    end
                    if ((row == 5'd2 || row == 5'd29 || col == 5'd2 || col == 5'd29) &&
                        (dist_x <= 6'd8 || dist_y <= 6'd8)) begin
                        sprite_pixel = frame[0] ? 4'h4 : 4'h8;
                    end
                    if (((row[4:1] == col[4:1]) || ((row[4:1] + col[4:1]) == 5'd15)) &&
                        (manhattan > 7'd7) && (manhattan < 7'd21)) begin
                        sprite_pixel = frame[1] ? 4'hD : 4'h5;
                    end
                end
                5'd12: begin
                    body = ((row >= 5'd8) && (row <= 5'd23) && (col >= 5'd5) && (col <= 5'd26)) ||
                           ((row >= 5'd12) && (row <= 5'd19) && (col >= 5'd1) && (col <= 5'd30));
                    if (body) begin
                        sprite_pixel = ((row >= 5'd11) && (row <= 5'd14) && (col >= 5'd12) && (col <= 5'd19)) ? 4'h8 : 4'h5;
                    end
                    if ((row >= 5'd14) && (row <= 5'd17) && (col >= 5'd14) && (col <= 5'd17)) begin
                        sprite_pixel = 4'h6;
                    end
                    if (((row >= 5'd5) && (row <= 5'd9) && (col >= 5'd12) && (col <= 5'd19)) ||
                        ((row >= 5'd22) && (row <= 5'd26) && (col >= 5'd10) && (col <= 5'd21))) begin
                        sprite_pixel = frame[0] ? 4'h9 : 4'h8;
                    end
                end
                5'd13: begin
                    dist_x = (col > 6'd15) ? {1'b0, (col - 6'd15)} : {1'b0, (6'd15 - col)};
                    dist_y = (row > 6'd15) ? {1'b0, (row - 6'd15)} : {1'b0, (6'd15 - row)};
                    manhattan = dist_x + dist_y;
                    if ((manhattan >= 7'd7) && (manhattan <= 7'd16)) begin
                        sprite_pixel = 4'hA;
                    end
                    if ((manhattan < 7'd8) || ((row >= 6'd13) && (row <= 6'd18) && (col >= 6'd13) && (col <= 6'd18))) begin
                        sprite_pixel = 4'h6;
                    end
                    if (((row >= 6'd3) && (row <= 6'd28) && (col >= 6'd15) && (col <= 6'd16)) ||
                        ((col >= 6'd3) && (col <= 6'd28) && (row >= 6'd15) && (row <= 6'd16))) begin
                        sprite_pixel = frame[0] ? 4'h9 : 4'hA;
                    end
                end
                5'd14, 5'd15, 5'd16: begin
                    sprite_pixel = 4'h0;
                end
                5'd17: begin
                    dist_x = (col > 6'd7) ? {1'b0, (col - 6'd7)} : {1'b0, (6'd7 - col)};
                    dist_y = (row > 6'd7) ? {1'b0, (row - 6'd7)} : {1'b0, (6'd7 - row)};
                    manhattan = dist_x + dist_y;
                    if ((manhattan >= 7'd5) && (manhattan <= 7'd9)) begin
                        sprite_pixel = frame[0] ? 4'h5 : 4'h8;
                    end
                    if ((manhattan <= 7'd3) || ((row[1:0] == frame[1:0]) && (dist_x <= 7'd6) && (dist_y <= 7'd6))) begin
                        sprite_pixel = 4'h6;
                    end
                end
                5'd18: begin
                    dist_x = (col > 6'd7) ? {1'b0, (col - 6'd7)} : {1'b0, (6'd7 - col)};
                    dist_y = (row > 6'd7) ? {1'b0, (row - 6'd7)} : {1'b0, (6'd7 - row)};
                    manhattan = dist_x + dist_y;
                    if (((dist_x <= 7'd1) && (dist_y <= 7'd6)) ||
                        ((dist_y <= 7'd1) && (dist_x <= 7'd6))) begin
                        sprite_pixel = 4'h6;
                    end
                    if ((dist_x == dist_y) && (manhattan <= 7'd10)) begin
                        sprite_pixel = frame[0] ? 4'h4 : 4'hE;
                    end
                    if (manhattan <= 7'd5) begin
                        sprite_pixel = 4'hF;
                    end
                end
                5'd19: begin
                    if (((row >= 6'd1) && (row <= 6'd14) && (col >= 6'd6) && (col <= 6'd9)) ||
                        ((row >= 6'd7) && (row <= 6'd12) && (col >= 6'd2) && (col <= 6'd13))) begin
                        sprite_pixel = ((col == 6'd7) || (col == 6'd8)) ? 4'h9 : 4'h4;
                    end
                    if (((row + col + {2'b00, frame}) & 6'h7) == 6'h0) begin
                        sprite_pixel = 4'h6;
                    end
                end
                5'd20: begin
                    dist_x = (col > 6'd7) ? {1'b0, (col - 6'd7)} : {1'b0, (6'd7 - col)};
                    dist_y = (row > 6'd7) ? {1'b0, (row - 6'd7)} : {1'b0, (6'd7 - row)};
                    manhattan = dist_x + dist_y;
                    body = ((dist_x <= 7'd5) && (dist_y <= 7'd3)) ||
                           ((dist_x <= 7'd3) && (dist_y <= 7'd5)) ||
                           ((dist_x <= 7'd4) && (dist_y <= 7'd4));
                    if (body) begin
                        sprite_pixel = 4'hA;
                    end
                    if ((dist_x <= 7'd2) && (dist_y <= 7'd2)) begin
                        sprite_pixel = 4'h6;
                    end
                    if (((manhattan == 7'd6) || (manhattan == 7'd7)) &&
                        (((row[1:0] + col[1:0] + frame[1:0]) & 2'b11) == 2'b00)) begin
                        sprite_pixel = frame[0] ? 4'h9 : 4'hF;
                    end
                end
                5'd21, 5'd22, 5'd23, 5'd24: begin
                    dist_x = (col > 6'd15) ? {1'b0, (col - 6'd15)} : {1'b0, (6'd15 - col)};
                    dist_y = (row > 6'd15) ? {1'b0, (row - 6'd15)} : {1'b0, (6'd15 - row)};
                    manhattan = dist_x + dist_y;
                    body = ((dist_x <= 7'd13) && (dist_y <= 7'd8)) ||
                           ((dist_x <= 7'd8) && (dist_y <= 7'd13)) ||
                           ((dist_x <= 7'd11) && (dist_y <= 7'd11));
                    if (body) begin
                        sprite_pixel = (sprite_type == 5'd21) ? 4'hA :
                                       ((sprite_type == 5'd22) ? 4'h9 :
                                       ((sprite_type == 5'd23) ? 4'hE : 4'h4));
                    end
                    if (((dist_x <= 7'd9) && (dist_y <= 7'd5)) ||
                        ((dist_x <= 7'd5) && (dist_y <= 7'd9)) ||
                        ((dist_x <= 7'd7) && (dist_y <= 7'd7))) begin
                        sprite_pixel = 4'h6;
                    end
                    if (sprite_type == 5'd21 &&
                        (((row >= 6'd8) && (row <= 6'd24) && (col >= 6'd11) && (col <= 6'd20)) ||
                         ((row >= 6'd20) && (row <= 6'd25) && (col >= 6'd14) && (col <= 6'd17)))) begin
                        sprite_pixel = frame[0] ? 4'h2 : 4'hA;
                    end
                    if (sprite_type == 5'd22 &&
                        (((row >= 6'd9) && (row <= 6'd13) && (col >= 6'd5) && (col <= 6'd26)) ||
                         ((row >= 6'd18) && (row <= 6'd24) && (col >= 6'd8) && (col <= 6'd23)))) begin
                        sprite_pixel = frame[0] ? 4'h8 : 4'h9;
                    end
                    if (sprite_type == 5'd23 &&
                        (((row >= 6'd7) && (row <= 6'd10) && (col >= 6'd9) && (col <= 6'd22)) ||
                         ((row >= 6'd21) && (row <= 6'd24) && (col >= 6'd9) && (col <= 6'd22)) ||
                         ((row >= 6'd11) && (row <= 6'd20) && (col >= 6'd14) && (col <= 6'd17)))) begin
                        sprite_pixel = frame[0] ? 4'hC : 4'hE;
                    end
                    if (sprite_type == 5'd24 &&
                        ((((dist_x <= 7'd2) && (dist_y <= 7'd11)) ||
                          ((dist_y <= 7'd2) && (dist_x <= 7'd11)) ||
                          ((dist_x >= 7'd7) && (dist_x <= 7'd10) &&
                           (dist_y >= 7'd7) && (dist_y <= 7'd10))) &&
                         (manhattan <= 7'd20))) begin
                        sprite_pixel = frame[0] ? 4'hF : 4'h4;
                    end
                end
                5'd25: begin
                    sprite_pixel = 4'h0;
                end
                default: begin
                    body = (row >= 4'd4) && (row <= 4'd11) && (col >= 4'd4) && (col <= 4'd11);
                    sprite_pixel = body ? 4'h6 : 4'h0;
                end
            endcase
        end
    endfunction

    logic [11:0] next_rgb;

    always_comb begin
        logic [11:0] rgb;
        logic force_colorbar;
        logic game_enable;
        logic blank_enable;
        logic [3:0] pixel_color;
        logic [2:0] pixel_tint;
        logic [9:0] sprite_x;
        logic [9:0] sprite_y;
        logic [4:0] sprite_type;
        logic [3:0] sprite_frame;
        logic sprite_visible;
        logic [3:0] sprite_sample;
        logic sprite_32;
        logic sprite_32x48;
        logic sprite_64;
        logic [5:0] sprite_rel_x;
        logic [5:0] sprite_rel_y;
        logic [10:0] sprite_width;
        logic [10:0] sprite_height;
        logic selected_sprite;
        logic [2:0] selected_tint;
        logic [4:0] selected_type;
        logic [3:0] selected_frame;
        logic [5:0] selected_rel_x;
        logic [5:0] selected_rel_y;
        logic [3:0] font_color;
        logic [31:0] text_pos;
        logic [9:0] text_x;
        logic [9:0] text_y;
        logic [6:0] char_count;
        logic [4:0] char_index;
        logic [1:0] word_index;
        logic [1:0] byte_index;
        logic [31:0] text_word;
        logic [7:0] char_code;
        logic [3:0] rel_y;
        logic [2:0] rel_x;
        logic [7:0] font_row_bits;
        logic [2:0] font_row;
        logic [2:0] font_col;
        logic font_core;
        logic font_glow;
        logic [5:0] selected_atlas_id;
        logic [15:0] selected_atlas_pixel;
        logic [10:0] scroll_y;
        logic [6:0] tile_x;
        logic [6:0] tile_y;

        rgb = 12'h000;
        force_colorbar = 1'b0;
        game_enable = 1'b0;
        blank_enable = 1'b0;
        pixel_color = 4'h0;
        pixel_tint = 3'h0;
        sprite_x = 10'h000;
        sprite_y = 10'h000;
        sprite_type = 5'h00;
        sprite_frame = 4'h0;
        sprite_visible = 1'b0;
        sprite_sample = 4'h0;
        sprite_32 = 1'b0;
        sprite_32x48 = 1'b0;
        sprite_64 = 1'b0;
        sprite_rel_x = 6'h00;
        sprite_rel_y = 6'h00;
        sprite_width = 11'd16;
        sprite_height = 11'd16;
        selected_sprite = 1'b0;
        selected_tint = 3'h0;
        selected_type = 5'h00;
        selected_frame = 4'h0;
        selected_rel_x = 6'h00;
        selected_rel_y = 6'h00;
        font_color = 4'h0;
        text_pos = 32'h0000_0000;
        text_x = 10'h000;
        text_y = 10'h000;
        char_count = 7'h00;
        char_index = 5'h00;
        word_index = 2'h0;
        byte_index = 2'h0;
        text_word = 32'h0000_0000;
        char_code = 8'h00;
        rel_y = 4'h0;
        rel_x = 3'h0;
        font_row_bits = 8'h00;
        font_row = 3'h0;
        font_col = 3'h0;
        font_core = 1'b0;
        font_glow = 1'b0;
        selected_atlas_id = 6'h3F;
        selected_atlas_pixel = 16'h0000;
        stage0_base_rgb = 12'h000;
        stage0_text_rgb = 12'h000;
        stage0_text_hit = 1'b0;
        stage0_sprite_hit = 1'b0;
        stage0_sprite_asset = 1'b0;
        stage0_sprite_tint = 3'h0;
        stage0_proc_sprite_sample = 4'h0;
        stage0_atlas_word = '0;
        stage0_atlas_nibble = 3'h0;
        stage0_force_black = 1'b0;
        stage0_force_colorbar = 1'b0;
        stage0_bg_x = pixel_x;
        stage0_bg_y = pixel_y;
        stage0_bg_scroll_y = pixel_y;
        scroll_y = pixel_y;
        tile_x = {1'b0, pixel_x[9:4]};
        tile_y = {1'b0, pixel_y[9:4]};
        bg_tile_pixel_addr = '0;

        game_enable = reg_array[CONTROL_WORD][0];
        force_colorbar = reg_array[CONTROL_WORD][1] || !game_enable;
        blank_enable = reg_array[CONTROL_WORD][2];
        scroll_y = pixel_y + {3'b000, frame_counter_pix[9:2]};
        stage0_bg_scroll_y = scroll_y;
        tile_y = {1'b0, scroll_y[9:4]};
        bg_tile_pixel_addr = bg_tilemap_word_addr(tile_x, tile_y);

        if (!pixel_valid || blank_enable) begin
            stage0_force_black = 1'b1;
        end else if (force_colorbar) begin
            stage0_force_colorbar = 1'b1;
        end else begin
            pixel_color = 4'h0;
            pixel_tint = 3'h0;
            selected_sprite = 1'b0;
            selected_tint = 3'h0;
            selected_type = 5'h00;
            selected_frame = 4'h0;
            selected_rel_x = 6'h00;
            selected_rel_y = 6'h00;
            // Choose the topmost candidate first, then render one sprite pixel.
            // This keeps the 2CG build under LUT budget instead of expanding the
            // procedural sprite decoder once per hardware slot.
            for (int i = 0; i < SPRITE_COUNT; i++) begin
                sprite_visible = reg_array[SPRITE_WORD_BASE + i][31];
                pixel_tint = {1'b0, reg_array[SPRITE_WORD_BASE + i][30:29]};
                sprite_type = reg_array[SPRITE_WORD_BASE + i][28:24];
                sprite_frame = reg_array[SPRITE_WORD_BASE + i][23:20];
                sprite_y = reg_array[SPRITE_WORD_BASE + i][19:10];
                sprite_x = reg_array[SPRITE_WORD_BASE + i][9:0];
                sprite_32 = ((sprite_type >= 5'd9) && (sprite_type <= 5'd13)) ||
                            ((sprite_type >= 5'd21) && (sprite_type <= 5'd25));
                sprite_32x48 = 1'b0;
                sprite_64 = (sprite_type >= 5'd14) && (sprite_type <= 5'd16);
                sprite_width = sprite_64 ? 11'd64 : ((sprite_32 || sprite_32x48) ? 11'd32 : 11'd16);
                sprite_height = sprite_64 ? 11'd64 : (sprite_32x48 ? 11'd48 : (sprite_32 ? 11'd32 : 11'd16));
                sprite_rel_x = sprite_64 ? (pixel_x[5:0] - sprite_x[5:0]) :
                               ((sprite_32 || sprite_32x48) ? {1'b0, (pixel_x[4:0] - sprite_x[4:0])} :
                                                              {2'b00, (pixel_x[3:0] - sprite_x[3:0])});
                sprite_rel_y = (sprite_64 || sprite_32x48) ? (pixel_y[5:0] - sprite_y[5:0]) :
                               (sprite_32 ? {1'b0, (pixel_y[4:0] - sprite_y[4:0])} :
                                            {2'b00, (pixel_y[3:0] - sprite_y[3:0])});
                if (sprite_visible &&
                    (pixel_x >= {1'b0, sprite_x}) && (pixel_x < ({1'b0, sprite_x} + sprite_width)) &&
                    (pixel_y >= {1'b0, sprite_y}) && (pixel_y < ({1'b0, sprite_y} + sprite_height))) begin
                    selected_sprite = 1'b1;
                    selected_tint = pixel_tint;
                    selected_type = sprite_type;
                    selected_frame = sprite_frame;
                    selected_rel_x = sprite_rel_x;
                    selected_rel_y = sprite_rel_y;
                end
            end
            if (selected_sprite) begin
                stage0_sprite_hit = 1'b1;
                stage0_sprite_tint = selected_tint;
                selected_atlas_id = runtime_atlas_frame_index(selected_type, selected_frame,
                                                              selected_rel_y, selected_rel_x);
                if (selected_atlas_id != 6'h3F) begin
                    selected_atlas_pixel = {selected_atlas_id, selected_rel_y[4:0], selected_rel_x[4:0]};
                    stage0_sprite_asset = 1'b1;
                    stage0_atlas_word = selected_atlas_pixel[15:3];
                    stage0_atlas_nibble = selected_atlas_pixel[2:0];
                end else begin
                    sprite_sample = sprite_pixel(selected_type, selected_frame, selected_rel_y, selected_rel_x);
                    stage0_proc_sprite_sample = sprite_sample;
                end
            end

            font_color = 4'h0;
            // Text is a hardware overlay used by the software HUD and state screens.
            for (int line = 0; line < TEXT_LINES; line++) begin
                text_pos = 32'h0000_0000;
                text_x = 10'h000;
                text_y = 10'h000;
                char_count = 7'h00;
                char_index = 5'h00;
                word_index = 2'h0;
                byte_index = 2'h0;
                text_word = 32'h0000_0000;
                char_code = 8'h00;
                rel_y = 4'h0;
                rel_x = 3'h0;
                font_row_bits = 8'h00;
                font_row = 3'h0;
                font_col = 3'h0;
                font_core = 1'b0;
                font_glow = 1'b0;

                text_pos = reg_array[TEXT_POS_BASE + line];
                text_x = text_pos[9:0];
                text_y = text_pos[19:10];
                char_count = text_pos[26:20];
                font_color = text_pos[31:28];
                if (text_pos[27] && (char_count != 0) &&
                    (pixel_x >= text_x) && (pixel_x < text_x + {char_count, 3'b000}) &&
                    (pixel_y >= text_y) && (pixel_y < text_y + 10'd16)) begin
                    char_index = (pixel_x - text_x) >> 3;
                    word_index = char_index[4:2];
                    byte_index = char_index[1:0];
                    text_word = reg_array[TEXT_WORD_BASE + line * 4 + word_index];
                    char_code = text_word[byte_index*8 +: 8];
                    rel_y = pixel_y[3:0] - text_y[3:0];
                    rel_x = pixel_x[2:0] - text_x[2:0];
                    font_row = rel_y[3:1];
                    font_col = rel_x;
                    font_row_bits = font_bits(char_code, font_row);
                    font_core = font_row_bits[3'd7 - font_col];
                    font_glow = 1'b0;
                    // Millennium-arcade text style: crisp core plus a right/down neon shadow.
                    if ((font_col != 3'd0) && font_sample(char_code, font_row, font_col - 3'd1)) begin
                        font_glow = 1'b1;
                    end
                    if ((font_row != 3'd0) && font_sample(char_code, font_row - 3'd1, font_col)) begin
                        font_glow = 1'b1;
                    end
                    if ((font_col != 3'd0) && (font_row != 3'd0) &&
                        font_sample(char_code, font_row - 3'd1, font_col - 3'd1)) begin
                        font_glow = 1'b1;
                    end
                    if (font_core) begin
                        stage0_text_hit = 1'b1;
                        stage0_text_rgb = palette(font_color, 3'h0);
                    end else if (font_glow) begin
                        stage0_text_hit = 1'b1;
                        stage0_text_rgb = palette(font_color, 3'd3);
                    end
                end
            end
        end
        stage0_base_rgb = rgb;
    end

    always_comb begin
        logic [6:0] stage1_tile_x;
        logic [6:0] stage1_tile_y;
        logic [1:0] bg_tile_px;
        stage1_asset_sprite_sample = (atlas_pixel_word >> {stage1_atlas_nibble, 2'b00}) & 4'hF;
        stage1_sprite_sample = stage1_sprite_asset ? stage1_asset_sprite_sample : stage1_proc_sprite_sample;
        stage1_tile_x = {1'b0, stage1_bg_x[9:4]};
        stage1_tile_y = {1'b0, stage1_bg_scroll_y[9:4]};
        if (stage1_bg_x >= 11'd488) begin
            stage1_bg_tile_id = panel_bg_tile(stage1_tile_x, stage1_tile_y);
            stage1_bg_chr_row = stage1_bg_y[3:1];
        end else begin
            stage1_bg_tile_id = bg_tilemap_sample_from_word(bg_tile_pixel_word, stage1_tile_x, stage1_tile_y);
            stage1_bg_chr_row = stage1_bg_scroll_y[3:1];
        end
        stage1_bg_chr_col = stage1_bg_x[3:1];
        bg_chr_pixel_addr = (stage1_bg_tile_id[7:6] == 2'b00) ?
                            BG_CHR_WORD_BITS'({stage1_bg_tile_id[5:0], stage1_bg_chr_row}) : '0;

        bg_tile_px = pic_bg_chr_pixel_from_word(bg_chr_pixel_word[15:0], stage2_bg_chr_col);
        if (stage2_force_black) begin
            stage2_base_rgb = 12'h000;
        end else if (stage2_force_colorbar) begin
            stage2_base_rgb = colorbar(stage2_bg_x);
        end else begin
            stage2_base_rgb = pic_bg_palette(bg_tile_px, stage2_bg_tile_id, stage2_bg_x, stage2_bg_scroll_y);
            if ((stage2_bg_x == 11'd488) || (stage2_bg_x == 11'd489)) begin
                stage2_base_rgb = 12'hC84;
            end else if ((stage2_bg_x == 11'd636) || (stage2_bg_x == 11'd637)) begin
                stage2_base_rgb = 12'h68A;
            end else if ((stage2_bg_x >= 11'd488) &&
                         ((stage2_bg_y[4:0] == 5'd0) || (stage2_bg_y[4:0] == 5'd1))) begin
                stage2_base_rgb = 12'h332;
            end
        end

        next_rgb = stage2_base_rgb;
        if (stage2_sprite_hit && (stage2_sprite_sample != 4'h0)) begin
            next_rgb = palette(stage2_sprite_sample, stage2_sprite_tint);
        end
        if (stage2_text_hit) begin
            next_rgb = stage2_text_rgb;
        end
    end

    always_ff @(posedge pixel_clk) begin
        if (!s_axi_aresetn) begin
            vga_r <= 4'h0;
            vga_g <= 4'h0;
            vga_b <= 4'h0;
            stage1_base_rgb <= 12'h000;
            stage1_text_rgb <= 12'h000;
            stage1_text_hit <= 1'b0;
            stage1_sprite_hit <= 1'b0;
            stage1_sprite_asset <= 1'b0;
            stage1_sprite_tint <= 3'h0;
            stage1_proc_sprite_sample <= 4'h0;
            stage1_atlas_nibble <= 3'h0;
            stage1_force_black <= 1'b1;
            stage1_force_colorbar <= 1'b0;
            stage1_bg_x <= 11'h0;
            stage1_bg_y <= 11'h0;
            stage1_bg_scroll_y <= 11'h0;
            stage2_text_rgb <= 12'h000;
            stage2_text_hit <= 1'b0;
            stage2_sprite_hit <= 1'b0;
            stage2_sprite_tint <= 3'h0;
            stage2_sprite_sample <= 4'h0;
            stage2_force_black <= 1'b1;
            stage2_force_colorbar <= 1'b0;
            stage2_bg_x <= 11'h0;
            stage2_bg_y <= 11'h0;
            stage2_bg_scroll_y <= 11'h0;
            stage2_bg_tile_id <= 8'h00;
            stage2_bg_chr_col <= 3'h0;
        end else begin
            stage1_base_rgb <= stage0_base_rgb;
            stage1_text_rgb <= stage0_text_rgb;
            stage1_text_hit <= stage0_text_hit;
            stage1_sprite_hit <= stage0_sprite_hit;
            stage1_sprite_asset <= stage0_sprite_asset;
            stage1_sprite_tint <= stage0_sprite_tint;
            stage1_proc_sprite_sample <= stage0_proc_sprite_sample;
            stage1_atlas_nibble <= stage0_atlas_nibble;
            stage1_force_black <= stage0_force_black;
            stage1_force_colorbar <= stage0_force_colorbar;
            stage1_bg_x <= stage0_bg_x;
            stage1_bg_y <= stage0_bg_y;
            stage1_bg_scroll_y <= stage0_bg_scroll_y;
            stage2_text_rgb <= stage1_text_rgb;
            stage2_text_hit <= stage1_text_hit;
            stage2_sprite_hit <= stage1_sprite_hit;
            stage2_sprite_tint <= stage1_sprite_tint;
            stage2_sprite_sample <= stage1_sprite_sample;
            stage2_force_black <= stage1_force_black;
            stage2_force_colorbar <= stage1_force_colorbar;
            stage2_bg_x <= stage1_bg_x;
            stage2_bg_y <= stage1_bg_y;
            stage2_bg_scroll_y <= stage1_bg_scroll_y;
            stage2_bg_tile_id <= stage1_bg_tile_id;
            stage2_bg_chr_col <= stage1_bg_chr_col;
            vga_r <= next_rgb[11:8];
            vga_g <= next_rgb[7:4];
            vga_b <= next_rgb[3:0];
        end
    end

endmodule
