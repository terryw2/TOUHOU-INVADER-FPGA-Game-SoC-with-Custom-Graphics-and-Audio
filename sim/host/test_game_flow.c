#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "audio_engine.h"
#include "game.h"
#include "hdmi_text_controller.h"
#include "lw_usb/keyboard.h"

volatile uint32_t hdmi_test_regs[HDMI_TEST_REG_WORDS];
volatile uint32_t audio_test_regs[16];

static HIDKeyboardReport mock_report;
static uint8_t mock_report_valid;
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

static unsigned sprite_visible(uint32_t word) {
    return (word >> 31) & 0x1U;
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

static void expect_text(uint8_t line, const char *expected, const char *message) {
    char actual[17];

    text_line(line, actual, sizeof(actual));
    if (strcmp(actual, expected) != 0) {
        fprintf(stderr, "FAIL: %s: expected '%s', got '%s'\n", message, expected, actual);
        exit(1);
    }
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

static void boot_game(void) {
    memset((void *)hdmi_test_regs, 0, sizeof(hdmi_test_regs));
    memset((void *)audio_test_regs, 0, sizeof(audio_test_regs));
    prev_restart = 0U;
    prev_pause = 0U;

    hdmi_text_controller_init();
    game_init();
    hdmi_text_controller_enable_game_output();
    audio_engine_init();
    render_game();
}

static void tick_game(uint8_t key0, uint8_t key1) {
    set_mock_keys(key0, key1);
    handle_usb_input();

    uint8_t menu_exit = (uint8_t)((get_key_pressed(KEY_R) != 0U) ||
                                  (get_key_pressed(KEY_Q) != 0U));
    if (menu_exit != 0U && prev_restart == 0U &&
        game_state != WAITING_START) {
        game_init();
    }
    prev_restart = menu_exit;

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

static void release_keys(void) {
    tick_game(0U, 0U);
}

static void run_frames(uint16_t count) {
    for (uint16_t i = 0U; i < count; i++) {
        tick_game(0U, 0U);
    }
}

int main(void) {
    unsigned player_x_before;
    unsigned player_x_paused;
    int16_t enemy_x_left;
    int16_t enemy_x_right;

    boot_game();
    expect_true(game_state == WAITING_START, "boot must open on menu");
    expect_text(1U, "ENDLESS NIGHT", "menu subtitle");

    tick_game(KEY_S, 0U);
    release_keys();
    tick_game(KEY_D, 0U);
    expect_text(4U, "TWO PLAYER", "menu can switch player count");
    release_keys();

    tick_game(KEY_S, 0U);
    release_keys();
    tick_game(KEY_D, 0U);
    expect_text(5U, "ENDLESS", "menu can switch arcade/endless mode");
    release_keys();
    tick_game(KEY_D, 0U);
    expect_text(5U, "ARCADE", "menu can switch back to arcade mode");
    release_keys();

    tick_game(KEY_SPACE, 0U);
    expect_true(game_state == PLAYING, "space starts the game");
    expect_text(7U, "TIME 7200", "start enters live play without a blocking countdown");
    expect_text(2U, "PLAYER 06", "HUD shows remaining lives clearly");
    expect_text(3U, "SPELL 3", "HUD shows spell stock clearly");
    expect_text(4U, "POWER 000", "HUD shows power separately");
    expect_text(8U, "RANKING", "HUD includes ranking title");
    expect_text(9U, "1 00000000", "HUD includes first ranking row");
    expect_text(13U, "5 00000000", "HUD includes fifth ranking row");
    expect_true(sprite_visible(SPRITE_WORD(PLAYER_SPRITE_SLOT)) != 0U, "player visible after start");
    expect_true(sprite_x(SPRITE_WORD(PLAYER_SPRITE_SLOT)) == 232U, "player start x");
    expect_true(sprite_y(SPRITE_WORD(PLAYER_SPRITE_SLOT)) == 424U, "player start y");
    expect_true(game_test_live_enemy_count() == 1U,
                "stage starts with one enemy instead of a full wave");
    expect_true(game_test_first_enemy_entry_ticks() != 0U,
                "first enemy starts in a boundary entry state");
    expect_true(game_test_first_enemy_y() < game_test_first_enemy_home_y(),
                "first enemy enters from the upper boundary instead of spawning at its lane");
    expect_true(game_test_enemy_spacing_ok() != 0U, "initial enemies do not overlap");
    run_frames(40U);
    expect_true(game_test_live_enemy_count() <= 1U,
                "enemy wave does not fill in immediately");
    expect_true(game_test_first_enemy_entry_ticks() == 0U,
                "first enemy finishes its gradual entry before AI movement");
    game_test_set_player_position(16, 424);
    run_frames(1U);
    enemy_x_left = game_test_first_enemy_x();
    game_test_set_player_position(456, 424);
    run_frames(1U);
    enemy_x_right = game_test_first_enemy_x();
    expect_true(enemy_x_right != enemy_x_left,
                "enemy AI reacts to the player's lane");
    game_test_set_player_position(232, 424);
    render_game();
    release_keys();

    player_x_before = sprite_x(SPRITE_WORD(PLAYER_SPRITE_SLOT));
    tick_game(KEY_A, 0U);
    expect_true(sprite_x(SPRITE_WORD(PLAYER_SPRITE_SLOT)) < player_x_before,
                "A key moves player left");
    expect_true(sprite_visible(SPRITE_WORD(PLAYER_BULLET_BASE_SLOT)) != 0U,
                "auto fire creates a bullet");
    release_keys();

    tick_game(KEY_ESC, 0U);
    expect_true(game_state == PAUSED, "ESC pauses");
    expect_text(7U, "PAUSED R MENU", "pause screen text");
    player_x_paused = sprite_x(SPRITE_WORD(PLAYER_SPRITE_SLOT));
    release_keys();
    tick_game(KEY_D, 0U);
    expect_true(sprite_x(SPRITE_WORD(PLAYER_SPRITE_SLOT)) == player_x_paused,
                "movement is frozen while paused");
    release_keys();

    tick_game(KEY_ESC, 0U);
    expect_true(game_state == PLAYING, "ESC resumes");
    release_keys();
    tick_game(KEY_D, 0U);
    expect_true(sprite_x(SPRITE_WORD(PLAYER_SPRITE_SLOT)) > player_x_paused,
                "D key moves player right after resume");
    release_keys();

    tick_game(KEY_Q, 0U);
    expect_true(game_state == WAITING_START, "Q exits active play to the menu");
    release_keys();
    tick_game(KEY_SPACE, 0U);
    expect_true(game_state == PLAYING, "space can restart from menu after Q exit");
    release_keys();

    run_frames(190U);
    game_test_spawn_powerup(2U,
                            (int16_t)sprite_x(SPRITE_WORD(PLAYER_SPRITE_SLOT)),
                            (int16_t)sprite_y(SPRITE_WORD(PLAYER_SPRITE_SLOT)));
    tick_game(0U, 0U);
    expect_true(game_test_power_level() == 1U, "collecting a power-up raises power level");
    expect_text(4U, "POWER 016", "HUD reports collected power-up state");

    game_test_damage_player(1U);
    render_game();
    expect_true(game_state == PLAYING, "shield hit keeps gameplay running");
    expect_true(shield == 2U, "shield hit consumes one shield");
    run_frames(100U);
    shield = 0U;
    lives = 2U;
    game_test_damage_player(1U);
    render_game();
    expect_true(game_state == PLAYING, "life hit respawns instead of pausing");
    expect_true(lives == 1U, "life hit consumes one life");
    expect_true(sprite_x(SPRITE_WORD(PLAYER_SPRITE_SLOT)) == 232U, "respawn returns player x");
    expect_true(sprite_y(SPRITE_WORD(PLAYER_SPRITE_SLOT)) == 424U, "respawn returns player y");
    run_frames(100U);

    game_test_force_boss_escort_case();
    expect_true(game_test_boss_visible() != 0U, "boss test setup keeps boss visible");
    expect_true(game_test_boss_entry_ticks() != 0U,
                "boss starts in a boundary entry state");
    expect_true(game_test_boss_y() < game_test_boss_home_y(),
                "boss enters from the upper boundary instead of spawning at its lane");
    run_frames(160U);
    expect_true(game_test_boss_visible() != 0U, "boss test setup keeps boss visible");
    expect_true(game_test_boss_entry_ticks() == 0U,
                "boss finishes its gradual entry before attack movement");
    expect_true(game_test_live_enemy_count() >= 1U, "boss stages refill escort enemies gradually");
    expect_true(game_test_enemy_spacing_ok() != 0U, "boss escorts do not overlap");

    shield = 1U;
    tick_game(KEY_X, 0U);
    expect_text(7U, "FOCUS", "X shows the focused movement state");
    release_keys();

    score = 12345UL;
    game_test_force_game_over();
    display_game_over();
    render_game();
    expect_text(9U, "1 00012345", "ranking records the latest top score");

    tick_game(KEY_R, 0U);
    expect_true(game_state == WAITING_START, "R restarts to menu");
    expect_text(1U, "ENDLESS NIGHT", "restart returns to menu");

    printf("test_game_flow PASS\n");
    return 0;
}
