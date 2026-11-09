#ifndef GAME_H
#define GAME_H

#include <stdint.h>

#define KEY_LEFT      0x50U
#define KEY_RIGHT     0x4FU
#define KEY_DOWN      0x51U
#define KEY_UP        0x52U
#define KEY_A         0x04U
#define KEY_D         0x07U
#define KEY_S         0x16U
#define KEY_W         0x1AU
#define KEY_Z         0x1DU
#define KEY_ENTER     0x28U
#define KEY_SPACE     0x2CU
#define KEY_X         0x1BU
#define KEY_Q         0x14U
#define KEY_R         0x15U
#define KEY_ESC       0x29U
#define KEY_KP_ENTER  0x58U

/* Keep the whole scene inside the 96 hardware sprite slots. */
#define NUM_ENEMY_ROWS       2
#define NUM_ENEMY_COLS       6
#define NUM_ENEMIES          (NUM_ENEMY_ROWS * NUM_ENEMY_COLS)
#define MAX_PLAYER_BULLETS   10
#define MAX_ENEMY_BULLETS    56
#define MAX_EXPLOSIONS       6

#define PLAYER_SPRITE_SLOT       0U
#define ENEMY_BASE_SLOT          1U
#define PLAYER_BULLET_BASE_SLOT  (ENEMY_BASE_SLOT + NUM_ENEMIES)
#define ENEMY_BULLET_BASE_SLOT   (PLAYER_BULLET_BASE_SLOT + MAX_PLAYER_BULLETS)
#define EXPLOSION_BASE_SLOT      (ENEMY_BULLET_BASE_SLOT + MAX_ENEMY_BULLETS)
#define POWERUP_SLOT             (EXPLOSION_BASE_SLOT + MAX_EXPLOSIONS)
#define ORBIT_BULLET_BASE_SLOT   (POWERUP_SLOT + 1U)
#define BOSS_SPRITE_SLOT         (ORBIT_BULLET_BASE_SLOT + 8U)
#define DECORATION_SLOT          95U

typedef enum {
    WAITING_START = 0,
    PLAYING,
    PAUSED,
    GAME_OVER,
    WIN
} GameState;

typedef struct {
    int16_t x;
    int16_t y;
    uint8_t visible;
    uint8_t sprite_type;
    uint8_t frame;
    uint8_t tint;
} Sprite;

typedef struct {
    int16_t x;
    int16_t y;
    uint8_t visible;
    int8_t vel_x;
    int8_t vel_y;
    uint8_t age;
} Bullet;

extern GameState game_state;
extern uint32_t score;
extern uint8_t lives;
extern uint8_t stage;
extern uint8_t shield;

void game_init(void);
void update_game(void);
void render_game(void);
void handle_usb_input(void);
uint8_t get_key_pressed(uint8_t key);
void toggle_pause(void);
uint8_t check_game_over(void);
uint8_t check_win(void);
void display_game_over(void);
void display_win(void);
uint32_t get_frame_counter(void);

#ifdef GAME_TEST_HOOKS
void game_test_spawn_powerup(uint8_t kind, int16_t x, int16_t y);
uint8_t game_test_power_level(void);
uint8_t game_test_weapon_mode(void);
uint8_t game_test_live_enemy_count(void);
uint8_t game_test_configured_enemy_count(void);
uint8_t game_test_enemy_spacing_ok(void);
void game_test_set_player_position(int16_t x, int16_t y);
int16_t game_test_first_enemy_x(void);
int16_t game_test_first_enemy_y(void);
int16_t game_test_first_enemy_home_y(void);
uint8_t game_test_first_enemy_entry_ticks(void);
uint8_t game_test_boss_visible(void);
int16_t game_test_boss_y(void);
int16_t game_test_boss_home_y(void);
uint8_t game_test_boss_entry_ticks(void);
void game_test_damage_player(uint8_t damage);
void game_test_force_game_over(void);
void game_test_force_boss_escort_case(void);
#endif

#endif
