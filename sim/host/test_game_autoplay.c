#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "audio_engine.h"
#include "game.h"
#include "hdmi_text_controller.h"

volatile uint32_t hdmi_test_regs[HDMI_TEST_REG_WORDS];
volatile uint32_t audio_test_regs[16];

static uint8_t prev_restart;
static uint8_t prev_pause;

#define REG_WORD(byte_addr)       ((byte_addr) / 4U)
#define SPRITE_WORD(index)        (hdmi_test_regs[(index)])
#define TEXT_WORD(index)          (hdmi_test_regs[REG_WORD(0x180U) + (index)])
#define TEXT_POS_WORD(line)       (hdmi_test_regs[REG_WORD(0x280U) + (line)])

static void fail(const char *message) {
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
}

static void expect_true(int condition, const char *message) {
    if (!condition) {
        fail(message);
    }
}

static unsigned sprite_x(uint32_t word) {
    return word & 0x3FFU;
}

static unsigned sprite_y(uint32_t word) {
    return (word >> 10) & 0x3FFU;
}

static void text_line(uint8_t line, char *out, size_t out_size) {
    uint32_t pos = TEXT_POS_WORD(line);
    uint8_t count = (uint8_t)((pos >> 20) & 0x7FU);

    if (out_size == 0U) {
        return;
    }
    if (count >= out_size) {
        count = (uint8_t)(out_size - 1U);
    }

    for (uint8_t i = 0U; i < count; i++) {
        uint32_t word = TEXT_WORD((uint8_t)(line * 4U + (i >> 2)));
        out[i] = (char)((word >> ((i & 3U) * 8U)) & 0xFFU);
    }
    out[count] = '\0';
}

static void expect_play_status_text(uint8_t line, const char *message) {
    char actual[17];

    text_line(line, actual, sizeof(actual));
    if (strncmp(actual, "TIME ", 5U) != 0 &&
        strncmp(actual, "BORDER ", 7U) != 0 &&
        strncmp(actual, "SPEED ", 6U) != 0 &&
        strcmp(actual, "SCORE X2") != 0 &&
        strcmp(actual, "FOCUS") != 0) {
        fprintf(stderr, "FAIL: %s: got '%s'\n", message, actual);
        exit(1);
    }
}

static void tick_autoplay(void) {
    handle_usb_input();

    if (get_key_pressed(KEY_R) != 0U && prev_restart == 0U) {
        game_init();
    }
    prev_restart = get_key_pressed(KEY_R);

    if (get_key_pressed(KEY_ESC) != 0U && prev_pause == 0U) {
        toggle_pause();
    }
    prev_pause = get_key_pressed(KEY_ESC);

    update_game();
    render_game();
    audio_engine_tick();

    if (check_game_over() != 0U) {
        display_game_over();
    } else if (check_win() != 0U) {
        display_win();
    }
}

static void run_autoplay_frames(uint16_t count) {
    for (uint16_t i = 0U; i < count; i++) {
        tick_autoplay();
    }
}

int main(void) {
    memset((void *)hdmi_test_regs, 0, sizeof(hdmi_test_regs));
    memset((void *)audio_test_regs, 0, sizeof(audio_test_regs));

    hdmi_text_controller_init();
    audio_engine_init();
    game_init();
    hdmi_text_controller_enable_game_output();
    render_game();

    expect_true(game_state == WAITING_START, "autoplay starts from menu");
    tick_autoplay();
    expect_true(game_state == PLAYING, "autoplay presses start from menu");
    expect_true(game_test_live_enemy_count() <= game_test_configured_enemy_count(),
                "autoplay stage uses the configured enemy count");
    expect_true(game_test_enemy_spacing_ok() != 0U, "autoplay enemies do not overlap");

    run_autoplay_frames(190U);
    expect_play_status_text(7U, "autoplay keeps a live HUD status visible");

    game_test_spawn_powerup(2U,
                            (int16_t)sprite_x(SPRITE_WORD(PLAYER_SPRITE_SLOT)),
                            (int16_t)sprite_y(SPRITE_WORD(PLAYER_SPRITE_SLOT)));
    tick_autoplay();
    expect_true(game_test_power_level() >= 1U, "autoplay can collect a spawned power-up");

    game_test_force_boss_escort_case();
    run_autoplay_frames(320U);
    expect_true(game_test_boss_visible() != 0U, "autoplay boss setup keeps boss alive");
    expect_true(game_test_live_enemy_count() >= 1U, "boss escort refill is automatic");
    expect_true(game_test_enemy_spacing_ok() != 0U, "autoplay boss escorts do not overlap");

    game_test_force_game_over();
    tick_autoplay();
    expect_true(game_state == WAITING_START, "autoplay restart key returns to menu after failure");
    tick_autoplay();
    expect_true(game_state == PLAYING, "autoplay starts again after failure restart");

    printf("test_game_autoplay PASS\n");
    return 0;
}
