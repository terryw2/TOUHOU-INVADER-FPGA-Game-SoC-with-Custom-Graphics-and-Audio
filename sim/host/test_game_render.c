#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "game.h"
#include "audio_engine.h"
#include "hdmi_text_controller.h"
#include "lw_usb/keyboard.h"

volatile uint32_t hdmi_test_regs[HDMI_TEST_REG_WORDS];
volatile uint32_t audio_test_regs[16];

static HIDKeyboardReport mock_report;
static uint8_t mock_report_valid;

#define REG_WORD(byte_addr)       ((byte_addr) / 4U)
#define SPRITE_WORD(index)        (hdmi_test_regs[(index)])
#define TEXT_WORD(index)          (hdmi_test_regs[REG_WORD(0x180U) + (index)])
#define TEXT_POS_WORD(line)       (hdmi_test_regs[REG_WORD(0x280U) + (line)])
#define CONTROL_WORD              (hdmi_test_regs[REG_WORD(0x3F0U)])

static void expect_true(int condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static unsigned sprite_x(uint32_t word) {
    return word & 0x3FFU;
}

static unsigned sprite_y(uint32_t word) {
    return (word >> 10) & 0x3FFU;
}

static unsigned sprite_type(uint32_t word) {
    return (word >> 24) & 0x1FU;
}

static unsigned sprite_visible(uint32_t word) {
    return (word >> 31) & 0x1U;
}

static int audio_any_volume(void) {
    return audio_test_regs[2] != 0U || audio_test_regs[6] != 0U || audio_test_regs[10] != 0U;
}

static void set_mock_keys(uint8_t key0, uint8_t key1) {
    memset(&mock_report, 0, sizeof(mock_report));
    mock_report.report_id = HID_KEYBOARD_REPORT_ID;
    mock_report.keycodes[0] = key0;
    mock_report.keycodes[1] = key1;
    mock_report_valid = 1U;
}

void usb_init(void) {
}

uint8_t usb_poll(void) {
    return mock_report_valid;
}

void usb_read_report(HIDKeyboardReport *report) {
    *report = mock_report;
    mock_report_valid = 0U;
}

int main(void) {
    memset((void *)hdmi_test_regs, 0xA5, sizeof(hdmi_test_regs));
    memset((void *)audio_test_regs, 0x00, sizeof(audio_test_regs));

    hdmi_text_controller_init();
    expect_true(CONTROL_WORD == HDMI_CONTROL_GAME_ENABLE,
                "HDMI init must enable game output");
    for (unsigned i = 0; i < HDMI_SPRITE_COUNT; i++) {
        expect_true(SPRITE_WORD(i) == 0U, "HDMI init must clear sprite table");
    }

    audio_engine_init();
    game_init();
    hdmi_text_controller_enable_game_output();
    render_game();

    expect_true(CONTROL_WORD == HDMI_CONTROL_GAME_ENABLE,
                "game output enable must clear colorbar self-test");
    expect_true(sprite_visible(SPRITE_WORD(0)) == 1U, "player sprite visible");
    expect_true(sprite_type(SPRITE_WORD(0)) == 25U, "player sprite type");
    expect_true(sprite_x(SPRITE_WORD(0)) == 112U, "menu player preview x");
    expect_true(sprite_y(SPRITE_WORD(0)) == 344U, "menu player preview y");

    for (unsigned i = 1U; i <= 7U; i++) {
        expect_true(sprite_visible(SPRITE_WORD(i)) == 1U,
                    "menu enemy preview sprites visible after render");
    }
    expect_true(sprite_visible(SPRITE_WORD(PLAYER_BULLET_BASE_SLOT)) == 0U,
                "player bullet slot invisible at boot");
    expect_true(sprite_visible(SPRITE_WORD(ENEMY_BULLET_BASE_SLOT)) == 0U,
                "enemy bullet slot 0 invisible at boot");
    expect_true(TEXT_WORD(0) == 0x36204E49U, "title text starts with IN 6");
    expect_true((TEXT_POS_WORD(0) & (1UL << 27)) != 0U,
                "score text line enabled");
    expect_true(game_state == WAITING_START,
                "game opens on menu before starting");

    set_mock_keys(KEY_D, 0U);
    handle_usb_input();
    update_game();
    render_game();
    expect_true(game_state == WAITING_START,
                "D key changes menu option without starting");

    set_mock_keys(KEY_SPACE, 0U);
    handle_usb_input();
    update_game();
    render_game();

    expect_true(game_state == PLAYING,
                "space starts the selected game");
    expect_true(sprite_x(SPRITE_WORD(0)) == 232U,
                "player starts centered after menu");
    expect_true(sprite_y(SPRITE_WORD(0)) == 424U,
                "player starts at bottom after menu");
    expect_true(sprite_visible(SPRITE_WORD(PLAYER_BULLET_BASE_SLOT)) == 0U,
                "first start frame only enters the game");

    set_mock_keys(KEY_W, 0U);
    handle_usb_input();
    update_game();
    render_game();
    expect_true(sprite_y(SPRITE_WORD(0)) == 419U,
                "hard difficulty W key moves player five pixels");
    expect_true(sprite_visible(SPRITE_WORD(PLAYER_BULLET_BASE_SLOT)) == 1U,
                "auto-fire creates visible player bullet");
    expect_true(sprite_type(SPRITE_WORD(PLAYER_BULLET_BASE_SLOT)) == 4U,
                "player bullet sprite type");
    expect_true(sprite_x(SPRITE_WORD(PLAYER_BULLET_BASE_SLOT)) == 247U,
                "player bullet x follows centered player");
    expect_true(sprite_y(SPRITE_WORD(PLAYER_BULLET_BASE_SLOT)) == 400U,
                "player bullet advances on the same nonblocking frame");
    expect_true(!audio_any_volume(),
                "shooting does not interrupt the global BGM with a per-shot sound");
    audio_engine_tick();
    expect_true(audio_any_volume(),
                "global BGM continues independently of event sounds");

    printf("test_game_render PASS\n");
    return 0;
}
