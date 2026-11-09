#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "audio_engine.h"
#include "game.h"
#include "hdmi_text_controller.h"
#include "lw_usb/keyboard.h"

volatile uint32_t hdmi_test_regs[HDMI_TEST_REG_WORDS];
volatile uint32_t audio_test_regs[16];

static HIDKeyboardReport mock_report;
static uint8_t mock_report_valid;

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

static void step_frame(uint8_t key0, uint8_t key1) {
    set_mock_keys(key0, key1);
    handle_usb_input();
    update_game();
    render_game();
    audio_engine_tick();
}

static void dump_regs(const char *mode, uint32_t frames) {
    printf("MODE %s\n", mode);
    printf("FRAMES %lu\n", (unsigned long)frames);
    printf("STATE %u\n", (unsigned)game_state);
    for (uint8_t i = 0U; i < HDMI_SPRITE_COUNT; i++) {
        printf("SPRITE %u %08lX\n", i, (unsigned long)hdmi_test_regs[i]);
    }
    for (uint8_t i = 0U; i < HDMI_TEXT_LINES * 4U; i++) {
        printf("TEXTWORD %u %08lX\n", i, (unsigned long)hdmi_test_regs[96U + i]);
    }
    for (uint8_t i = 0U; i < HDMI_TEXT_LINES; i++) {
        printf("TEXTPOS %u %08lX\n", i, (unsigned long)hdmi_test_regs[160U + i]);
    }
}

int main(int argc, char **argv) {
    const char *mode = (argc > 1) ? argv[1] : "menu";
    uint32_t frames = 0U;

    memset((void *)hdmi_test_regs, 0, sizeof(hdmi_test_regs));
    memset((void *)audio_test_regs, 0, sizeof(audio_test_regs));

    hdmi_text_controller_init();
    audio_engine_init();
    game_init();
    hdmi_text_controller_enable_game_output();
    render_game();

    if (strcmp(mode, "menu") == 0) {
        for (uint32_t i = 0U; i < 96U; i++) {
            step_frame(0U, 0U);
            frames++;
        }
    } else if (strcmp(mode, "game") == 0) {
        step_frame(KEY_SPACE, 0U);
        frames++;
        for (uint32_t i = 0U; i < 230U; i++) {
            uint8_t key0 = (i & 0x20U) ? KEY_A : KEY_D;
            step_frame(key0, 0U);
            frames++;
        }
    } else if (strcmp(mode, "hard2p") == 0) {
        step_frame(KEY_D, 0U);
        step_frame(KEY_S, 0U);
        step_frame(KEY_D, 0U);
        step_frame(KEY_SPACE, 0U);
        frames += 4U;
        for (uint32_t i = 0U; i < 260U; i++) {
            uint8_t key0 = (i & 0x10U) ? KEY_A : KEY_D;
            uint8_t key1 = (i & 0x08U) ? KEY_W : KEY_S;
            step_frame(key0, key1);
            frames++;
        }
    }

    dump_regs(mode, frames);
    return 0;
}
