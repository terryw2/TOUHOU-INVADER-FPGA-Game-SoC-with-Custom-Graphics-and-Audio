#include "platform.h"

#ifndef MB_NO_STDOUT
#include "xil_printf.h"
#define MB_PRINTF(...) xil_printf(__VA_ARGS__)
#else
#define MB_PRINTF(...) do { } while (0)
#endif

#include "audio_engine.h"
#include "ddr_runtime.h"
#include "game.h"
#include "hdmi_text_controller.h"
#ifndef MB_NO_USB
#include "lw_usb/keyboard.h"
#endif
#include "memory_test.h"

#define APP_VERSION "U250505v6"
#define APP_STATUS_PERIOD_FRAMES 120U
#define DDR_READY_TIMEOUT 120000000UL

static const char *state_name(GameState state) {
    switch (state) {
    case WAITING_START:
        return "WAITING_START";
    case PLAYING:
        return "PLAYING";
    case PAUSED:
        return "PAUSED";
    case GAME_OVER:
        return "GAME_OVER";
    case WIN:
        return "WIN";
    default:
        return "UNKNOWN";
    }
}

static void print_app_status(const char *status, uint32_t frame_cnt) {
    MB_PRINTF("[URBANA] ver=%s proc=APP status=%s frame=%lu state=%s stage=%u lives=%u shield=%u score=%lu\r\n",
              APP_VERSION, status, (unsigned long)frame_cnt,
              state_name(game_state), stage, lives, shield,
              (unsigned long)score);
}

int main(void) {
    uint32_t prev_frame = 0U;
    uint32_t last_status_frame = 0U;
    uint8_t prev_menu_exit = 0U;
    uint8_t prev_pause = 0U;
    GameState last_reported_state = WAITING_START;
    uint8_t ddr_ok;

    init_platform();
    MB_PRINTF("\r\n[URBANA] ver=%s proc=APP status=APP_START\r\n", APP_VERSION);
    MB_PRINTF("[URBANA] ver=%s proc=APP status=INIT_PLATFORM_DONE\r\n", APP_VERSION);

    hdmi_text_controller_init();
    hdmi_text_controller_clear_text();
    hdmi_text_controller_set_text_line(0U, "URBANA BRAM DDR", 0xEU);
    hdmi_text_controller_set_text_line(1U, "BOOT START", 0x2U);
    hdmi_text_controller_enable_game_output();
    MB_PRINTF("[URBANA] ver=%s proc=APP status=HDMI_BOOT_STATUS_ON\r\n", APP_VERSION);

    hdmi_text_controller_set_text_line(1U, "DDR WAIT", 0xEU);
    MB_PRINTF("[URBANA] ver=%s proc=APP status=DDR_WAIT_BEGIN\r\n", APP_VERSION);
    if (ddr_runtime_wait_ready(DDR_READY_TIMEOUT) == 0U) {
        MB_PRINTF("[URBANA] ver=%s proc=APP status=DDR_WAIT_TIMEOUT\r\n", APP_VERSION);
        hdmi_text_controller_clear_text();
        hdmi_text_controller_set_text_line(0U, "URBANA BRAM DDR", 0xEU);
        hdmi_text_controller_set_text_line(1U, "DDR WAIT ERR", 0x4U);
        hdmi_text_controller_enable_game_output();
        while (1) {
            for (volatile uint32_t delay = 0U; delay < 20000000UL; delay++) {
            }
            MB_PRINTF("[URBANA] ver=%s proc=APP status=DDR_WAIT_TIMEOUT_HEARTBEAT\r\n", APP_VERSION);
        }
    }
    MB_PRINTF("[URBANA] ver=%s proc=APP status=DDR_READY\r\n", APP_VERSION);
    ddr_runtime_clear_bss();
    MB_PRINTF("[URBANA] ver=%s proc=APP status=DDR_BSS_CLEAR bytes=%lu\r\n",
              APP_VERSION, (unsigned long)ddr_runtime_bss_bytes());

    hdmi_text_controller_clear_text();
    hdmi_text_controller_set_text_line(0U, "URBANA BRAM DDR", 0xEU);
    hdmi_text_controller_set_text_line(1U, "DDR READY", 0x2U);
    MB_PRINTF("[URBANA] ver=%s proc=APP status=HDMI_INIT_DONE\r\n", APP_VERSION);
    game_init();
    print_app_status("GAME_INIT_DONE", 0U);
    hdmi_text_controller_enable_game_output();
    render_game();

    MB_PRINTF("[URBANA] ver=%s proc=APP status=FIRST_RENDER_DONE\r\n", APP_VERSION);

    MB_PRINTF("[URBANA] ver=%s proc=APP status=AUDIO_INIT_BEGIN\r\n", APP_VERSION);
    audio_engine_init();
    MB_PRINTF("[URBANA] ver=%s proc=APP status=AUDIO_INIT_DONE\r\n", APP_VERSION);
#ifdef MB_ENABLE_DDR_TEST
    MB_PRINTF("[URBANA] ver=%s proc=APP status=DDR_TEST_BEGIN\r\n", APP_VERSION);
    ddr_ok = ddr3_memory_test();
    MB_PRINTF("[URBANA] ver=%s proc=APP status=DDR_TEST_DONE result=%u\r\n",
              APP_VERSION, ddr_ok);
#else
    ddr_ok = 1U;
    MB_PRINTF("[URBANA] ver=%s proc=APP status=DDR_TEST_SKIPPED\r\n", APP_VERSION);
#endif
#ifndef MB_NO_USB
    MB_PRINTF("[URBANA] ver=%s proc=APP status=USB_INIT_BEGIN\r\n", APP_VERSION);
    usb_init();
    MB_PRINTF("[URBANA] ver=%s proc=APP status=USB_INIT_DONE\r\n", APP_VERSION);
#else
    MB_PRINTF("[URBANA] ver=%s proc=APP status=USB_DISABLED\r\n", APP_VERSION);
#endif
    if (ddr_ok != 0U) {
#ifdef MB_DDR4_STATUS_BIST
        hdmi_text_controller_set_text_line(7U, "RAM4 PASS", 0x2U);
#else
        hdmi_text_controller_set_text_line(7U, "RAM PASS", 0x2U);
#endif
    } else {
#ifdef MB_DDR4_STATUS_BIST
        hdmi_text_controller_set_text_line(7U, "RAM4 ERR", 0x4U);
#else
        hdmi_text_controller_set_text_line(7U, "RAM ERR", 0x4U);
#endif
    }

    render_game();
    print_app_status("APP_READY", get_frame_counter());

    while (1) {
        uint32_t frame_cnt = get_frame_counter();

        if (frame_cnt != prev_frame) {
            uint8_t menu_exit;
            /* Use the HDMI frame counter as the game tick so update/render target 60 FPS. */
            prev_frame = frame_cnt;
            handle_usb_input();

            menu_exit = (uint8_t)((get_key_pressed(KEY_R) != 0U) ||
                                  (get_key_pressed(KEY_Q) != 0U));
            if (menu_exit != 0U && prev_menu_exit == 0U &&
                game_state != WAITING_START) {
                game_init();
                print_app_status("MENU_EXIT", frame_cnt);
            }
            prev_menu_exit = menu_exit;

            if (get_key_pressed(KEY_ESC) != 0U && prev_pause == 0U) {
                toggle_pause();
                print_app_status("PAUSE_TOGGLE", frame_cnt);
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

            if (game_state != last_reported_state) {
                last_reported_state = game_state;
                print_app_status("STATE_CHANGE", frame_cnt);
            } else if ((uint32_t)(frame_cnt - last_status_frame) >= APP_STATUS_PERIOD_FRAMES) {
                last_status_frame = frame_cnt;
                print_app_status("HEARTBEAT", frame_cnt);
            }
        }
    }

    cleanup_platform();
    return 0;
}
