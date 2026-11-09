#include "hdmi_text_controller.h"

#include "generated_gfx_assets.h"

volatile uint32_t *hdmi_regs = (volatile uint32_t *)HDMI_BASE_ADDR;

static uint8_t tree_tile_for(uint8_t rel_x, uint8_t rel_y) {
    return (uint8_t)(16U + rel_y * 8U + rel_x);
}

static uint8_t bg_object_tile(uint8_t tile_x, uint8_t tile_y) {
    static const uint8_t tree_pos[] = {
        0U, 0U, 21U, 3U, 2U, 13U, 20U, 17U, 1U, 25U
    };
    static const uint8_t bush_pos[] = {
        11U, 7U, 18U, 11U, 8U, 22U, 25U, 30U
    };
    static const uint8_t rock_pos[] = {
        14U, 5U, 9U, 15U, 18U, 23U, 27U, 12U, 5U, 29U
    };

    for (uint8_t i = 0U; i < (uint8_t)sizeof(tree_pos); i += 2U) {
        uint8_t ox = tree_pos[i];
        uint8_t oy = tree_pos[i + 1U];
        if (tile_x >= ox && tile_x < (uint8_t)(ox + 8U) &&
            tile_y >= oy && tile_y < (uint8_t)(oy + 6U)) {
            return tree_tile_for((uint8_t)(tile_x - ox), (uint8_t)(tile_y - oy));
        }
    }

    for (uint8_t i = 0U; i < (uint8_t)sizeof(bush_pos); i += 2U) {
        uint8_t ox = bush_pos[i];
        uint8_t oy = bush_pos[i + 1U];
        if (tile_x >= ox && tile_x < (uint8_t)(ox + 2U) &&
            tile_y >= oy && tile_y < (uint8_t)(oy + 2U)) {
            if (tile_y == oy) {
                return (tile_x == ox) ? 12U : 13U;
            }
            return (tile_x == ox) ? 14U : 15U;
        }
    }

    for (uint8_t i = 0U; i < (uint8_t)sizeof(rock_pos); i += 2U) {
        if (tile_x == rock_pos[i] && tile_y == rock_pos[i + 1U]) {
            return (i & 0x2U) ? 11U : 10U;
        }
    }

    return 0xFFU;
}

static uint8_t bg_tile_for(uint8_t tile_x, uint8_t tile_y, uint32_t seed) {
    uint8_t object_tile = bg_object_tile(tile_x, tile_y);
    uint8_t h = (uint8_t)((tile_x * 37U) ^ (tile_y * 73U) ^
                          ((tile_x + tile_y + (uint8_t)seed) * 11U) ^
                          (uint8_t)(seed >> ((tile_x + tile_y) & 7U)));
    uint8_t y_band = (uint8_t)((tile_y >> 3) & 0x3U);
    uint8_t road_center = 15U;
    uint8_t road_width = 4U;
    uint8_t dx;

    if (object_tile != 0xFFU) {
        return object_tile;
    }

    if (y_band == 1U) {
        road_center = 13U;
    } else if (y_band == 2U) {
        road_center = 17U;
    } else if (y_band == 3U) {
        road_center = 14U;
    }

    road_center = (uint8_t)(road_center + ((tile_y & 0x4U) ? 1U : 0U));
    road_width = (uint8_t)(road_width + ((h >> 5) & 0x1U));
    dx = (tile_x > road_center) ? (uint8_t)(tile_x - road_center) :
                                  (uint8_t)(road_center - tile_x);

    if (dx < road_width) {
        return (h & 0x08U) ? 2U : 3U;
    }
    if (dx == road_width) {
        return (tile_x < road_center) ? 4U : 5U;
    }
    if ((h & 0x3FU) == 0x21U) {
        return 7U;
    }
    if ((h & 0x2FU) == 0x0AU) {
        return 6U;
    }
    return (h & 0x18U) ? 1U : 0U;
}

static uint32_t pack_sprite(int16_t x, int16_t y, uint8_t sprite_type,
                            uint8_t frame, uint8_t visible, uint8_t tint) {
    uint32_t sprite_data = 0;
    sprite_data |= ((uint32_t)(visible != 0U)) << SPRITE_VISIBLE_SHIFT;
    sprite_data |= ((uint32_t)tint & 0x3U) << SPRITE_TINT_SHIFT;
    sprite_data |= ((uint32_t)sprite_type & 0x1FU) << SPRITE_TYPE_SHIFT;
    sprite_data |= ((uint32_t)frame & 0xFU) << SPRITE_FRAME_SHIFT;
    sprite_data |= ((uint32_t)y & 0x3FFU) << SPRITE_Y_SHIFT;
    sprite_data |= ((uint32_t)x & 0x3FFU) << SPRITE_X_SHIFT;
    return sprite_data;
}

void hdmi_text_controller_init(void) {
    HDMI_CONTROL = HDMI_CONTROL_BLANK;
    hdmi_text_controller_load_runtime_assets();
    hdmi_text_controller_load_background(0x6B09A5C3UL);
    hdmi_text_controller_clear_sprites();
    hdmi_text_controller_clear_text();
    HDMI_CONTROL = HDMI_CONTROL_GAME_ENABLE;
}

void hdmi_text_controller_enable_game_output(void) {
    HDMI_CONTROL = HDMI_CONTROL_GAME_ENABLE;
}

void hdmi_text_controller_force_colorbar(uint8_t enable) {
    HDMI_CONTROL = enable ? HDMI_CONTROL_FORCE_COLORBAR : HDMI_CONTROL_GAME_ENABLE;
}

void hdmi_text_controller_set_bg_palette(uint8_t index, uint16_t rgb444) {
    if (index >= HDMI_BG_PALETTE_WORDS) {
        return;
    }

    HDMI_BG_PALETTE(index) = (uint32_t)(rgb444 & 0x0FFFU);
}

void hdmi_text_controller_load_runtime_assets(void) {
    uint16_t bg_count = (GFX_BG_CHR_WORD_COUNT < HDMI_BG_CHR_WORDS) ?
                        GFX_BG_CHR_WORD_COUNT : HDMI_BG_CHR_WORDS;

    for (uint16_t i = 0U; i < bg_count; i++) {
        HDMI_BG_CHR_WORD(i) = (uint32_t)g_gfx_bg_chr_words[i];
    }

    for (uint16_t i = 0U; i < GFX_ATLAS_WORD_COUNT; i++) {
        HDMI_GFX_ATLAS_WORD(i) = g_gfx_atlas_words[i];
    }
}

void hdmi_text_controller_load_background(uint32_t seed) {
    hdmi_text_controller_set_bg_palette(0U, 0x052U);
    hdmi_text_controller_set_bg_palette(1U, 0x173U);
    hdmi_text_controller_set_bg_palette(2U, 0x5B4U);
    hdmi_text_controller_set_bg_palette(3U, 0x964U);

    for (uint8_t y = 0U; y < HDMI_BG_TILE_H; y++) {
        for (uint8_t word_x = 0U; word_x < (HDMI_BG_TILE_W / 4U); word_x++) {
            uint32_t word = 0U;
            for (uint8_t slot = 0U; slot < 4U; slot++) {
                uint8_t x = (uint8_t)(word_x * 4U + slot);
                uint8_t tile = bg_tile_for(x, y, seed);
                word |= ((uint32_t)tile) << (slot * 8U);
            }
            HDMI_BG_TILE_WORD((uint16_t)y * (HDMI_BG_TILE_W / 4U) + word_x) = word;
        }
    }
}

void hdmi_text_controller_set_sprite(uint8_t index, int16_t x, int16_t y,
                                     uint8_t sprite_type, uint8_t frame,
                                     uint8_t visible, uint8_t tint) {
    if (index >= HDMI_SPRITE_COUNT) {
        return;
    }

    HDMI_SPRITE_TABLE(index) = pack_sprite(x, y, sprite_type, frame, visible, tint);
}

void hdmi_text_controller_clear_sprites(void) {
    for (uint8_t i = 0; i < HDMI_SPRITE_COUNT; i++) {
        HDMI_SPRITE_TABLE(i) = 0U;
    }
}

void hdmi_text_controller_set_text_line(uint8_t line, const char *text, uint8_t color) {
    hdmi_text_controller_set_text_at(line, 20U, (uint16_t)(10U + line * 20U), text, color);
}

void hdmi_text_controller_set_text_at(uint8_t line, uint16_t x, uint16_t y,
                                      const char *text, uint8_t color) {
    uint8_t char_count = 0U;

    if (line >= HDMI_TEXT_LINES || text == 0) {
        return;
    }

    while (char_count < 16U && text[char_count] != '\0') {
        char_count++;
    }

    HDMI_TEXT_POS(line) = (((uint32_t)color & 0xFU) << 28) |
                          (1UL << 27) |
                          (((uint32_t)char_count & 0x7FU) << 20) |
                          (((uint32_t)y & 0x3FFU) << 10) |
                          ((uint32_t)x & 0x3FFU);

    for (uint8_t word_index = 0U; word_index < 4U; word_index++) {
        uint32_t word = 0U;
        for (uint8_t byte_index = 0U; byte_index < 4U; byte_index++) {
            uint8_t char_index = (uint8_t)(word_index * 4U + byte_index);
            if (char_index < char_count) {
                word |= ((uint32_t)text[char_index] & 0xFFU) << (byte_index * 8U);
            }
        }
        HDMI_TEXT_BUFFER(line * 4U + word_index) = word;
    }
}

void hdmi_text_controller_clear_text_line(uint8_t line) {
    if (line >= HDMI_TEXT_LINES) {
        return;
    }

    HDMI_TEXT_POS(line) = 0U;
    for (uint8_t word_index = 0U; word_index < 4U; word_index++) {
        HDMI_TEXT_BUFFER(line * 4U + word_index) = 0U;
    }
}

void hdmi_text_controller_clear_text(void) {
    for (uint8_t i = 0U; i < HDMI_TEXT_LINES; i++) {
        hdmi_text_controller_clear_text_line(i);
    }
}

uint32_t hdmi_text_controller_frame_counter(void) {
    return HDMI_FRAME_CNT;
}
