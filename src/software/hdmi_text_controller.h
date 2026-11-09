#ifndef HDMI_TEXT_CONTROLLER_H
#define HDMI_TEXT_CONTROLLER_H

#include <stdint.h>

#ifndef HDMI_BASE_ADDR
# ifdef XPAR_HDMI_TEXT_CONTROLLER_0_BASEADDR
#  define HDMI_BASE_ADDR XPAR_HDMI_TEXT_CONTROLLER_0_BASEADDR
# elif defined(XPAR_HDMI_TEXT_CONTROLLER_0_S_AXI_BASEADDR)
#  define HDMI_BASE_ADDR XPAR_HDMI_TEXT_CONTROLLER_0_S_AXI_BASEADDR
# elif defined(XPAR_HDMI_TEXT_CONTROLLER_V1_0_0_BASEADDR)
#  define HDMI_BASE_ADDR XPAR_HDMI_TEXT_CONTROLLER_V1_0_0_BASEADDR
# elif defined(XPAR_HDMI_TEXT_CONTROLLER_V1_0_BASEADDR)
#  define HDMI_BASE_ADDR XPAR_HDMI_TEXT_CONTROLLER_V1_0_BASEADDR
# else
#  define HDMI_BASE_ADDR 0x44A00000U
# endif
#endif

#define HDMI_SPRITE_TABLE(i)   (*(volatile uint32_t *)(HDMI_BASE_ADDR + ((i) * 4U)))
#define HDMI_TEXT_BUFFER(i)    (*(volatile uint32_t *)(HDMI_BASE_ADDR + 0x180U + ((i) * 4U)))
#define HDMI_TEXT_POS(i)       (*(volatile uint32_t *)(HDMI_BASE_ADDR + 0x280U + ((i) * 4U)))
#define HDMI_SHIELD(i)         (*(volatile uint32_t *)(HDMI_BASE_ADDR + 0x2C0U + ((i) * 4U)))
#define HDMI_AUDIO_CTRL        (*(volatile uint32_t *)(HDMI_BASE_ADDR + 0x3E0U))
#define HDMI_CONTROL           (*(volatile uint32_t *)(HDMI_BASE_ADDR + 0x3F0U))
#define HDMI_FRAME_CNT         (*(volatile uint32_t *)(HDMI_BASE_ADDR + 0x3F4U))
#define HDMI_DRAW_X            (*(volatile uint32_t *)(HDMI_BASE_ADDR + 0x3F8U))
#define HDMI_DRAW_Y            (*(volatile uint32_t *)(HDMI_BASE_ADDR + 0x3FCU))
#define HDMI_BG_TILE_WORD(i)   (*(volatile uint32_t *)(HDMI_BASE_ADDR + 0x400U + ((i) * 4U)))
#define HDMI_BG_PALETTE(i)     (*(volatile uint32_t *)(HDMI_BASE_ADDR + 0x800U + ((i) * 4U)))
#define HDMI_BG_CHR_WORD(i)    (*(volatile uint32_t *)(HDMI_BASE_ADDR + 0x840U + ((i) * 4U)))
#define HDMI_GFX_ATLAS_WORD(i) (*(volatile uint32_t *)(HDMI_BASE_ADDR + 0x1040U + ((i) * 4U)))

#define HDMI_CONTROL_GAME_ENABLE      0x00000001U
#define HDMI_CONTROL_FORCE_COLORBAR   0x00000002U
#define HDMI_CONTROL_BLANK            0x00000004U

#define SPRITE_VISIBLE_SHIFT 31
#define SPRITE_TINT_SHIFT    29
#define SPRITE_TYPE_SHIFT    24
#define SPRITE_FRAME_SHIFT   20
#define SPRITE_Y_SHIFT       10
#define SPRITE_X_SHIFT       0

#define SPRITE_VISIBLE_MASK  0x80000000U
#define SPRITE_TINT_MASK     0x60000000U
#define SPRITE_TYPE_MASK     0x1F000000U
#define SPRITE_FRAME_MASK    0x00F00000U
#define SPRITE_Y_MASK        0x000FFC00U
#define SPRITE_X_MASK        0x000003FFU

#define HDMI_SPRITE_COUNT    96U
#define HDMI_TEXT_LINES      16U
#define HDMI_BG_TILE_W       32U
#define HDMI_BG_TILE_H       32U
#define HDMI_BG_TILE_WORDS   256U
#define HDMI_BG_PALETTE_WORDS 4U
#define HDMI_BG_CHR_WORDS    512U

void hdmi_text_controller_init(void);
void hdmi_text_controller_enable_game_output(void);
void hdmi_text_controller_force_colorbar(uint8_t enable);
void hdmi_text_controller_set_bg_palette(uint8_t index, uint16_t rgb444);
void hdmi_text_controller_load_runtime_assets(void);
void hdmi_text_controller_load_background(uint32_t seed);
void hdmi_text_controller_set_sprite(uint8_t index, int16_t x, int16_t y,
                                     uint8_t sprite_type, uint8_t frame,
                                     uint8_t visible, uint8_t tint);
void hdmi_text_controller_clear_sprites(void);
void hdmi_text_controller_set_text_line(uint8_t line, const char *text, uint8_t color);
void hdmi_text_controller_set_text_at(uint8_t line, uint16_t x, uint16_t y,
                                      const char *text, uint8_t color);
void hdmi_text_controller_clear_text_line(uint8_t line);
void hdmi_text_controller_clear_text(void);
uint32_t hdmi_text_controller_frame_counter(void);

#endif
