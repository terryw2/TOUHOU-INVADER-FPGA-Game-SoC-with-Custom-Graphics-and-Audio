#include "game.h"

#include "audio_engine.h"
#include "game_assets.h"
#include "hdmi_text_controller.h"
#include "memory_sections.h"
#ifndef MB_NO_USB
#include "lw_usb/keyboard.h"
#endif

#define PLAYFIELD_LEFT 8
#define PLAYFIELD_RIGHT 480
#define PLAYFIELD_TOP 8
#define HUD_LEFT 488
#define HUD_TEXT_X 500
#define PLAYER_MIN_X 16
#define PLAYER_MAX_X 456
#define PLAYER_MIN_Y 56
#define PLAYER_MAX_Y 432
#define PLAYER_START_X 232
#define PLAYER_START_Y 424
#define PLAYER_HITBOX_X 8
#define PLAYER_HITBOX_Y 18
#define PLAYER_HITBOX_W 16
#define PLAYER_HITBOX_H 16
#define PLAYER_PICKUP_X 6
#define PLAYER_PICKUP_Y 14
#define PLAYER_PICKUP_W 20
#define PLAYER_PICKUP_H 24
#define PLAYER_FIRE_INTERVAL 7U
#define READY_START_TICKS 0U
#define READY_STAGE_TICKS 0U
#define GAME_OVER_RESTART_TICKS 0U
#define SHIELD_MAX 3U
#define STAGE_COUNT 6U
#define DIFFICULTY_COUNT 3U
#define MENU_ITEM_COUNT 3U
#define FIRE_LEVEL_MAX 3U
#define POWER_LEVEL_MAX 3U
#define SPEED_BOOST_BONUS 2U
#define ENEMY_MAX_HP 8U
#define ENEMY_SPAWN_MIN_DX 44
#define ENEMY_SPAWN_MIN_DY 30
#define ENEMY_RENDER_MIN_DX 34
#define ENEMY_RENDER_MIN_DY 26
#define SPR_PLAYER_LARGE 25U
#define SPR_ENEMY_WING_LARGE 10U
#define SPR_ENEMY_ORB_LARGE 11U
#define SPR_ENEMY_BLADE_LARGE 12U
#define SPR_POWERUP_LARGE 13U
#define SPR_BOSS_SMALL 14U
#define SPR_BOSS_MID 15U
#define SPR_BOSS_BIG 16U
#define SPR_ENEMY_RING_BULLET 17U
#define SPR_ENEMY_SHARD_BULLET 18U
#define SPR_PLAYER_SPLIT_BULLET 19U
#define SPR_OPTION_ORB 20U
#define SPR_POWERUP_SHIELD 21U
#define SPR_POWERUP_WEAPON 22U
#define SPR_POWERUP_TIMER 23U
#define SPR_POWERUP_BOMB 24U
#define POWERUP_KIND_COUNT 8U
#define PLAYER_COUNT 2U
#define PLAYER2_SPRITE_SLOT DECORATION_SLOT

typedef struct {
    const char *name;
    uint16_t fall_period;
    uint16_t dive_period;
    uint8_t fire_period;
    uint8_t enemy_bullet_speed;
    uint8_t enemy_wave_count;
    uint8_t boss_escort_target;
    uint8_t boss_escort_spawn;
    uint16_t boss_hp_base;
    uint16_t time_limit;
} StageConfig;

typedef struct {
    const char *name;
    uint8_t player_speed;
    uint8_t player_bullet_speed;
    uint8_t enemy_period_percent;
    int8_t enemy_speed_delta;
    uint8_t start_shield;
    uint8_t start_lives;
    int8_t enemy_count_delta;
    int8_t escort_delta;
    uint8_t enemy_hit_damage;
} DifficultyConfig;

typedef struct {
    int16_t x;
    int16_t y;
    uint8_t visible;
    uint8_t frame;
    uint8_t ttl;
} Explosion;

/* Per-stage tuning table: lower periods and higher bullet speeds raise difficulty. */
static const StageConfig stage_config[STAGE_COUNT] = {
    {"FIREFLY", 430U, 500U, 96U, 2U, 8U, 0U, 0U, 0U, 7200U},
    {"HUMAN", 400U, 480U, 90U, 2U, 9U, 3U, 1U, 56U, 7800U},
    {"BAMBOO", 372U, 460U, 84U, 3U, 10U, 4U, 1U, 76U, 8500U},
    {"RABBIT", 344U, 440U, 78U, 3U, 11U, 5U, 1U, 96U, 9200U},
    {"EIRIN", 318U, 420U, 72U, 4U, 12U, 6U, 2U, 128U, 9999U},
    {"KAGUYA 6B", 292U, 400U, 68U, 4U, 12U, 7U, 2U, 164U, 9999U},
};

/* Menu-selected difficulty affects both player feel and enemy pressure. */
static const DifficultyConfig difficulty_config[DIFFICULTY_COUNT] = {
    {"EASY", 5U, 9U, 116U, -1, SHIELD_MAX, 4U, -1, -1, 1U},
    {"NORMAL", 5U, 8U, 92U, 0, SHIELD_MAX, 3U, 0, 0, 1U},
    {"HARD", 5U, 7U, 82U, 1, 2U, 2U, 1, 1, 1U},
};

GameState game_state = WAITING_START;
uint32_t score = 0;
uint8_t lives = 3;
uint8_t stage = 1;
uint8_t shield = SHIELD_MAX;

Sprite players[PLAYER_COUNT] DDR_BSS_SECTION;
#define player players[0]
Sprite enemies[NUM_ENEMIES] DDR_BSS_SECTION;
Bullet player_bullets[MAX_PLAYER_BULLETS] DDR_BSS_SECTION;
Bullet enemy_bullets[MAX_ENEMY_BULLETS] DDR_BSS_SECTION;
Explosion explosions[MAX_EXPLOSIONS] DDR_BSS_SECTION;
Sprite powerup;
Sprite boss;

static uint8_t keys_pressed[256] DDR_BSS_SECTION;
static uint8_t prev_keys[256] DDR_BSS_SECTION;
static uint32_t frame_ticks;
static int8_t enemy_dir;
static uint32_t prng_state;
static uint8_t focus_active;
static uint8_t invincible_ticks;
static uint32_t graze_score;
static uint16_t point_items;
static uint16_t stage_timer;
static uint8_t ready_ticks;
static uint8_t weapon_mode;
static uint8_t power_level;
static uint16_t combo;
static uint8_t combo_timer;
static uint8_t score_recorded;
static uint32_t high_scores[5] DDR_BSS_SECTION;
static uint16_t boss_hp;
static uint16_t boss_hp_max;
static uint8_t boss_kind;
static int16_t boss_home_x;
static int16_t boss_home_y;
static uint8_t boss_entry_ticks;
static uint8_t powerup_kind;
static uint8_t fire_level;
static uint16_t speed_ticks;
static uint16_t barrier_ticks;
static uint16_t score_boost_ticks;
static uint8_t game_over_ticks;
static uint8_t menu_cursor;
static uint8_t selected_difficulty = 1U;
static uint8_t selected_players = 1U;
static uint8_t selected_endless = 0U;
static int16_t enemy_home_x[NUM_ENEMIES] DDR_BSS_SECTION;
static int16_t enemy_home_y[NUM_ENEMIES] DDR_BSS_SECTION;
static uint8_t enemy_entry_ticks[NUM_ENEMIES] DDR_BSS_SECTION;
static uint8_t enemy_entry_axis[NUM_ENEMIES] DDR_BSS_SECTION;
static uint8_t enemy_hp[NUM_ENEMIES] DDR_BSS_SECTION;
static uint8_t enemy_spawn_target;
static uint8_t enemy_spawn_cursor;

static int16_t clamp_i16(int16_t value, int16_t min_value, int16_t max_value);
static int16_t abs_i16(int16_t value);
static int16_t move_towards_i16(int16_t value, int16_t target, int16_t step);
static uint8_t active_player_count(void);
static uint8_t player_is_active(uint8_t index);
static uint8_t target_player_index_for_point(int16_t x, int16_t y);
static Sprite *target_player_for_point(int16_t x, int16_t y);
static int16_t lowest_active_player_y(void);
static void reset_player_sprite(uint8_t index);
static uint8_t stage_pressure(void);
static uint8_t configured_enemy_count(void);
static void clear_enemy_bullets(void);
static void apply_player_damage_to(uint8_t player_index, uint8_t damage);
static uint8_t live_enemy_count(void);
static void respawn_boss_escorts(void);
static uint8_t find_clear_enemy_position(int16_t *x, int16_t *y,
                                         uint8_t skip_index,
                                         uint8_t row_hint,
                                         uint8_t col_hint);

static uint8_t text_append(char *dst, uint8_t pos, const char *src) {
    while (*src != '\0' && pos < 16U) {
        dst[pos++] = *src++;
    }
    dst[pos] = '\0';
    return pos;
}

static uint8_t text_append_u32(char *dst, uint8_t pos, uint32_t value, uint8_t min_digits) {
    char digits[10];
    uint8_t count = 0U;

    do {
        digits[count++] = (char)('0' + (value % 10UL));
        value /= 10UL;
    } while (value != 0UL && count < (uint8_t)sizeof(digits));

    while (count < min_digits && count < (uint8_t)sizeof(digits)) {
        digits[count++] = '0';
    }

    while (count != 0U && pos < 16U) {
        dst[pos++] = digits[--count];
    }
    dst[pos] = '\0';
    return pos;
}

static void text_copy(char *dst, const char *src) {
    dst[0] = '\0';
    (void)text_append(dst, 0U, src);
}

static void text_join(char *dst, const char *a, const char *b) {
    uint8_t pos;

    dst[0] = '\0';
    pos = text_append(dst, 0U, a);
    (void)text_append(dst, pos, b);
}

static void text_label_u32(char *dst, const char *label, uint32_t value, uint8_t min_digits) {
    uint8_t pos;

    dst[0] = '\0';
    pos = text_append(dst, 0U, label);
    (void)text_append_u32(dst, pos, value, min_digits);
}

static void text_rank(char *dst, uint8_t rank, uint32_t value) {
    uint8_t pos;

    dst[0] = '\0';
    pos = text_append_u32(dst, 0U, rank, 1U);
    pos = text_append(dst, pos, " ");
    (void)text_append_u32(dst, pos, value % 100000000UL, 8U);
}

static void hide_sprite_slot(uint8_t slot) {
    hdmi_text_controller_set_sprite(slot, 0, 0, 0U, 0U, 0U, 0U);
}

static void add_score(uint32_t amount) {
    score += amount * (score_boost_ticks != 0U ? 2UL : 1UL);
}

static uint16_t timed_powerup_duration(void) {
    uint16_t base = selected_difficulty == 0U ? 540U : (selected_difficulty == 1U ? 420U : 300U);
    uint16_t pressure_trim = (uint16_t)(stage_pressure() * 8U);
    return (base > pressure_trim + 180U) ? (uint16_t)(base - pressure_trim) : 180U;
}

static uint8_t powerup_sprite_for_kind(uint8_t kind) {
    switch (kind % POWERUP_KIND_COUNT) {
        case 0U:
        case 5U:
            return SPR_POWERUP_SHIELD;
        case 1U:
        case 2U:
        case 3U:
            return SPR_POWERUP_WEAPON;
        case 4U:
        case 6U:
            return SPR_POWERUP_TIMER;
        default:
            return SPR_POWERUP_BOMB;
    }
}

static uint8_t powerup_drop_mask(void) {
    if (selected_difficulty == 0U) {
        return stage_pressure() >= 8U ? 0x7U : 0x3U;
    }
    if (selected_difficulty == 2U) {
        return stage_pressure() >= 8U ? 0x1FU : 0xFU;
    }
    return stage_pressure() >= 8U ? 0xFU : 0x7U;
}

static uint8_t key_edge(uint8_t key) {
    return (keys_pressed[key] != 0U) && (prev_keys[key] == 0U);
}

static uint8_t active_player_count(void) {
    return selected_players == 2U ? 2U : 1U;
}

static uint8_t player_is_active(uint8_t index) {
    return (index < active_player_count()) && (players[index].visible != 0U);
}

static int16_t player_start_x(uint8_t index) {
    if (active_player_count() == 2U) {
        return index == 0U ? PLAYER_START_X : (int16_t)(PLAYER_START_X + 44);
    }
    return PLAYER_START_X;
}

static void reset_player_sprite(uint8_t index) {
    players[index].x = player_start_x(index);
    players[index].y = PLAYER_START_Y;
    players[index].visible = index < active_player_count() ? 1U : 0U;
    players[index].sprite_type = SPR_PLAYER_LARGE;
    players[index].frame = 0U;
    players[index].tint = index;
}

static uint8_t target_player_index_for_point(int16_t x, int16_t y) {
    uint8_t best = 0U;
    int16_t best_distance = 32767;

    for (uint8_t i = 0U; i < active_player_count(); i++) {
        if (players[i].visible != 0U) {
            int16_t dx = abs_i16((int16_t)(players[i].x - x));
            int16_t dy = abs_i16((int16_t)(players[i].y - y));
            int16_t distance = (int16_t)(dx + dy);

            if (distance < best_distance) {
                best_distance = distance;
                best = i;
            }
        }
    }
    return best;
}

static Sprite *target_player_for_point(int16_t x, int16_t y) {
    return &players[target_player_index_for_point(x, y)];
}

static int16_t lowest_active_player_y(void) {
    int16_t lowest = player.y;

    for (uint8_t i = 1U; i < active_player_count(); i++) {
        if (players[i].visible != 0U && players[i].y > lowest) {
            lowest = players[i].y;
        }
    }
    return lowest;
}

static uint8_t stage_index(void) {
    uint8_t normalized_stage = (stage == 0U) ? 1U : stage;
    return (uint8_t)((normalized_stage - 1U) % STAGE_COUNT);
}

static uint8_t stage_pressure(void) {
    uint8_t cap = selected_endless != 0U ? 15U : STAGE_COUNT;
    if (stage == 0U) {
        return 1U;
    }
    return stage > cap ? cap : stage;
}

static const DifficultyConfig *difficulty(void) {
    return &difficulty_config[selected_difficulty % DIFFICULTY_COUNT];
}

static uint16_t scaled_period(uint16_t base_period) {
    uint32_t scaled = (uint32_t)base_period * difficulty()->enemy_period_percent;
    scaled = (scaled + 50UL) / 100UL;
    if (scaled < 12UL) {
        scaled = 12UL;
    }
    if (selected_endless != 0U && stage > STAGE_COUNT) {
        uint32_t trim = (uint32_t)(stage - STAGE_COUNT) * 2UL;
        scaled = (scaled > (12UL + trim)) ? (scaled - trim) : 12UL;
    }
    return (uint16_t)scaled;
}

static uint8_t scaled_enemy_bullet_speed(void) {
    int16_t speed = (int16_t)stage_config[stage_index()].enemy_bullet_speed +
                    difficulty()->enemy_speed_delta;
    if (selected_endless != 0U && stage > STAGE_COUNT) {
        speed = (int16_t)(speed + clamp_i16((int16_t)((stage - STAGE_COUNT) / 3U), 0, 2));
    }
    return (uint8_t)clamp_i16(speed, 2, 5);
}

static uint8_t player_damage_amount(void) {
    uint8_t damage = (uint8_t)(1U + fire_level);

    if (weapon_mode == 2U && power_level >= 2U) {
        damage++;
    }
    return (uint8_t)clamp_i16(damage, 1, 5);
}

static uint8_t player_move_speed(void) {
    uint8_t speed = difficulty()->player_speed;

    if (focus_active != 0U) {
        return 2U;
    }
    if (speed_ticks != 0U) {
        speed = (uint8_t)(speed + SPEED_BOOST_BONUS);
    }
    return (uint8_t)clamp_i16(speed, 3, 8);
}

static uint8_t player_fire_interval(void) {
    int16_t interval = PLAYER_FIRE_INTERVAL;

    interval = (int16_t)(interval - (int16_t)fire_level * 2);
    if (weapon_mode == 2U) {
        interval = (int16_t)(interval - 1);
    }
    return (uint8_t)clamp_i16(interval, 4, PLAYER_FIRE_INTERVAL);
}

static uint8_t stage_has_boss(void) {
    if (stage < 2U) {
        return 0U;
    }
    if (selected_endless != 0U) {
        return (uint8_t)(((stage % 3U) == 0U) ? 1U : 0U);
    }
    return 1U;
}

static uint8_t stage_boss_kind(void) {
    if (stage_has_boss() == 0U) {
        return 0U;
    }
    return (uint8_t)((stage_pressure() >= 8U) ? 2U : ((stage_pressure() >= 5U) ? 1U : 0U));
}

static uint8_t configured_enemy_count(void) {
    int16_t count = (int16_t)stage_config[stage_index()].enemy_wave_count +
                    (int16_t)difficulty()->enemy_count_delta;

    if (selected_endless != 0U && stage > STAGE_COUNT) {
        count = (int16_t)(count + clamp_i16((int16_t)((stage - STAGE_COUNT + 1U) / 2U), 0, 5));
    }
    if (stage_has_boss() != 0U) {
        count = (int16_t)(count - 3 - stage_boss_kind());
    }
    return (uint8_t)clamp_i16(count, 4, NUM_ENEMIES);
}

static uint8_t configured_escort_target(void) {
    int16_t target = (int16_t)stage_config[stage_index()].boss_escort_target +
                     (int16_t)difficulty()->escort_delta;

    if (boss.visible == 0U) {
        return 0U;
    }
    if (selected_endless != 0U && stage > STAGE_COUNT) {
        target = (int16_t)(target + clamp_i16((int16_t)((stage - STAGE_COUNT) / 3U), 0, 3));
    }
    return (uint8_t)clamp_i16(target, 0, 10);
}

static uint8_t configured_escort_spawn_count(void) {
    int16_t count = (int16_t)stage_config[stage_index()].boss_escort_spawn;

    if (selected_difficulty == 2U) {
        count++;
    }
    return (uint8_t)clamp_i16(count, 0, 3);
}

static uint16_t configured_boss_hp(void) {
    uint16_t hp = stage_config[stage_index()].boss_hp_base;

    if (hp == 0U) {
        return 0U;
    }
    hp = (uint16_t)(hp + stage_pressure() * 8U + stage_boss_kind() * 24U);
    if (selected_endless != 0U && stage > STAGE_COUNT) {
        hp = (uint16_t)(hp + (stage - STAGE_COUNT) * 12U);
    }
    if (selected_difficulty == 0U) {
        hp = (uint16_t)(hp * 85U / 100U);
    } else if (selected_difficulty == 2U) {
        hp = (uint16_t)(hp * 125U / 100U);
    }
    return hp;
}

static uint8_t configured_enemy_hp(uint8_t row, uint8_t flavor) {
    int16_t hp = 1 + (int16_t)(stage_pressure() / 4U) + (int16_t)(flavor & 0x1U);

    if (row >= 2U) {
        hp++;
    }
    if (selected_difficulty == 0U) {
        hp--;
    } else if (selected_difficulty == 2U) {
        hp++;
    }
    if (selected_endless != 0U && stage > STAGE_COUNT) {
        hp = (int16_t)(hp + clamp_i16((int16_t)((stage - STAGE_COUNT) / 3U), 0, 3));
    }
    return (uint8_t)clamp_i16(hp, 1, ENEMY_MAX_HP);
}

static uint8_t live_enemy_count(void) {
    uint8_t count = 0U;

    for (uint8_t i = 0U; i < NUM_ENEMIES; i++) {
        if (enemies[i].visible != 0U) {
            count++;
        }
    }
    return count;
}

static uint8_t boxes_overlap(int16_t ax, int16_t ay, int16_t aw, int16_t ah,
                             int16_t bx, int16_t by, int16_t bw, int16_t bh) {
    return (ax < bx + bw) && (ax + aw > bx) && (ay < by + bh) && (ay + ah > by);
}

static int16_t abs_i16(int16_t value) {
    return value < 0 ? (int16_t)-value : value;
}

static int16_t clamp_i16(int16_t value, int16_t min_value, int16_t max_value) {
    if (value < min_value) {
        return min_value;
    }
    if (value > max_value) {
        return max_value;
    }
    return value;
}

static int16_t move_towards_i16(int16_t value, int16_t target, int16_t step) {
    if (value < target) {
        int16_t next = (int16_t)(value + step);
        return next > target ? target : next;
    }
    if (value > target) {
        int16_t next = (int16_t)(value - step);
        return next < target ? target : next;
    }
    return value;
}

static int16_t wave16(uint32_t phase) {
    uint8_t p = (uint8_t)(phase & 0x3FU);
    if (p < 16U) {
        return (int16_t)p;
    }
    if (p < 48U) {
        return (int16_t)(32 - (int16_t)p);
    }
    return (int16_t)((int16_t)p - 64);
}

static void spawn_explosion(int16_t x, int16_t y) {
    uint8_t slot = 0U;

    for (uint8_t i = 0U; i < MAX_EXPLOSIONS; i++) {
        if (explosions[i].visible == 0U) {
            slot = i;
            break;
        }
    }

    explosions[slot].x = x;
    explosions[slot].y = y;
    explosions[slot].visible = 1U;
    explosions[slot].frame = 0U;
    explosions[slot].ttl = 18U;
}

static uint32_t next_rand(void) {
    prng_state = prng_state * 1664525UL + 1013904223UL;
    return prng_state;
}

static uint8_t enemy_position_clear(int16_t x, int16_t y, uint8_t skip_index) {
    for (uint8_t i = 0U; i < NUM_ENEMIES; i++) {
        if (i != skip_index && enemies[i].visible != 0U) {
            if (abs_i16((int16_t)(x - enemy_home_x[i])) < ENEMY_SPAWN_MIN_DX &&
                abs_i16((int16_t)(y - enemy_home_y[i])) < ENEMY_SPAWN_MIN_DY) {
                return 0U;
            }
        }
    }
    return 1U;
}

static void set_enemy_slot(uint8_t index, int16_t x, int16_t y, uint8_t row, uint8_t flavor) {
    enemy_home_x[index] = clamp_i16(x, PLAYFIELD_LEFT, (int16_t)(PLAYFIELD_RIGHT - 32));
    enemy_home_y[index] = clamp_i16(y, 32, 190);
    enemy_entry_axis[index] = (row == 0U) ? 0U : (uint8_t)(1U + (flavor & 1U));
    enemy_entry_ticks[index] = (uint8_t)(24U + (flavor & 0x7U) * 2U);
    if (enemy_entry_axis[index] == 1U) {
        enemies[index].x = PLAYFIELD_LEFT;
        enemies[index].y = enemy_home_y[index];
    } else if (enemy_entry_axis[index] == 2U) {
        enemies[index].x = (int16_t)(PLAYFIELD_RIGHT - 32);
        enemies[index].y = enemy_home_y[index];
    } else {
        enemies[index].x = enemy_home_x[index];
        enemies[index].y = PLAYFIELD_TOP;
    }
    enemies[index].visible = 1U;
    enemies[index].sprite_type = (uint8_t)(SPR_ENEMY_WING_LARGE + (flavor % 3U));
    enemies[index].frame = (uint8_t)(next_rand() & 0x3U);
    enemies[index].tint = (uint8_t)((row + flavor + next_rand()) & 0x3U);
    enemy_hp[index] = configured_enemy_hp(row, flavor);
}

static uint8_t spawn_sequence_enemy(uint8_t sequence_index) {
    for (uint8_t slot = 0U; slot < NUM_ENEMIES; slot++) {
        if (enemies[slot].visible == 0U) {
            uint8_t row = (uint8_t)((sequence_index / NUM_ENEMY_COLS) % NUM_ENEMY_ROWS);
            uint8_t col = (uint8_t)((sequence_index * 2U + row + stage) % NUM_ENEMY_COLS);
            int16_t x;
            int16_t y;

            if (find_clear_enemy_position(&x, &y, slot, row, col) == 0U) {
                x = clamp_i16((int16_t)(38 + col * 68), PLAYFIELD_LEFT, (int16_t)(PLAYFIELD_RIGHT - 32));
                y = clamp_i16((int16_t)(48 + row * 42), 32, 190);
            }
            set_enemy_slot(slot, x, y, row, (uint8_t)(sequence_index + stage_pressure()));
            return 1U;
        }
    }
    return 0U;
}

static uint8_t find_clear_enemy_position(int16_t *x, int16_t *y,
                                         uint8_t skip_index,
                                         uint8_t row_hint,
                                         uint8_t col_hint) {
    for (uint8_t attempt = 0U; attempt < 24U; attempt++) {
        int16_t jitter_x = (int16_t)((int16_t)((next_rand() >> 2) & 0x1FU) - 15);
        int16_t jitter_y = (int16_t)((int16_t)((next_rand() >> 7) & 0x0FU) - 7);
        uint8_t lane = (uint8_t)((col_hint + attempt * 2U + row_hint) % NUM_ENEMY_COLS);
        uint8_t row = (uint8_t)((row_hint + attempt / NUM_ENEMY_COLS) % NUM_ENEMY_ROWS);
        int16_t candidate_x = clamp_i16((int16_t)(38 + lane * 68 + jitter_x),
                                        PLAYFIELD_LEFT, (int16_t)(PLAYFIELD_RIGHT - 32));
        int16_t candidate_y = clamp_i16((int16_t)(48 + row * 42 + jitter_y), 32, 190);

        if (enemy_position_clear(candidate_x, candidate_y, skip_index) != 0U) {
            *x = candidate_x;
            *y = candidate_y;
            return 1U;
        }
    }
    return 0U;
}

static void spawn_enemies(void) {
    uint8_t count = configured_enemy_count();

    for (uint8_t i = 0U; i < NUM_ENEMIES; i++) {
        enemies[i].visible = 0U;
        enemies[i].frame = 0U;
        enemies[i].tint = 0U;
        enemy_home_x[i] = 0;
        enemy_home_y[i] = 0;
        enemy_entry_ticks[i] = 0U;
        enemy_entry_axis[i] = 0U;
        enemy_hp[i] = 0U;
    }

    boss.visible = 0U;
    boss_hp = 0U;
    boss_hp_max = 0U;
    boss_kind = 0U;
    boss_home_x = 0;
    boss_home_y = 0;
    boss_entry_ticks = 0U;
    if (stage_has_boss() != 0U) {
        boss_kind = stage_boss_kind();
        boss_home_x = boss_kind == 2U ? 198 : (boss_kind == 1U ? 214 : 230);
        boss_home_y = boss_kind == 2U ? 38 : 46;
        boss.x = boss_home_x;
        boss.y = PLAYFIELD_TOP;
        boss.visible = 1U;
        boss.sprite_type = (uint8_t)(SPR_BOSS_SMALL + boss_kind);
        boss.frame = 0U;
        boss.tint = boss_kind;
        boss_entry_ticks = (uint8_t)(48U + boss_kind * 10U);
        boss_hp_max = configured_boss_hp();
        boss_hp = boss_hp_max;
    }

    enemy_spawn_target = count;
    enemy_spawn_cursor = 0U;
    if (enemy_spawn_cursor < enemy_spawn_target && spawn_sequence_enemy(enemy_spawn_cursor) != 0U) {
        enemy_spawn_cursor++;
    }
}

static void reset_play_session(void) {
    score = 0U;
    lives = (uint8_t)(selected_players * difficulty()->start_lives);
    stage = 1U;
    shield = difficulty()->start_shield;
    frame_ticks = 0U;
    enemy_dir = 1;
    prng_state = 0x3852026UL ^
                 (hdmi_text_controller_frame_counter() * 1103515245UL) ^
                 ((uint32_t)selected_difficulty << 16) ^
                 ((uint32_t)selected_players << 8) ^
                 (uint32_t)selected_endless;
    focus_active = 0U;
    invincible_ticks = 0U;
    graze_score = 0U;
    point_items = 0U;
    stage_timer = stage_config[0].time_limit;
    ready_ticks = 0U;
    weapon_mode = 0U;
    power_level = 0U;
    fire_level = 0U;
    combo = 0U;
    combo_timer = 0U;
    score_recorded = 0U;
    powerup_kind = 0U;
    speed_ticks = 0U;
    barrier_ticks = 0U;
    score_boost_ticks = 0U;
    game_over_ticks = 0U;

    for (uint8_t i = 0U; i < PLAYER_COUNT; i++) {
        reset_player_sprite(i);
    }

    spawn_enemies();

    for (uint8_t i = 0U; i < MAX_PLAYER_BULLETS; i++) {
        player_bullets[i].visible = 0U;
    }
    for (uint8_t i = 0U; i < MAX_ENEMY_BULLETS; i++) {
        enemy_bullets[i].visible = 0U;
    }
    for (uint8_t i = 0U; i < MAX_EXPLOSIONS; i++) {
        explosions[i].visible = 0U;
        explosions[i].ttl = 0U;
    }
    powerup.visible = 0U;
    powerup.sprite_type = SPR_POWERUP_SHIELD;
    powerup.frame = 0U;
    powerup.tint = 0U;
    boss.visible = 0U;
    boss_hp = 0U;
    boss_hp_max = 0U;
    boss_kind = 0U;

    hdmi_text_controller_clear_sprites();
    hdmi_text_controller_clear_text();
}

void game_init(void) {
    game_state = WAITING_START;
    menu_cursor = 0U;
    reset_play_session();
}

static void start_selected_game(void) {
    reset_play_session();
    game_state = PLAYING;
    ready_ticks = READY_START_TICKS;
    audio_engine_play_boot();
}

static void update_menu(void) {
    frame_ticks++;

    if (key_edge(KEY_W) || key_edge(KEY_UP) || key_edge(KEY_S) || key_edge(KEY_DOWN)) {
        if (key_edge(KEY_W) || key_edge(KEY_UP)) {
            menu_cursor = (uint8_t)((menu_cursor + MENU_ITEM_COUNT - 1U) % MENU_ITEM_COUNT);
        } else {
            menu_cursor = (uint8_t)((menu_cursor + 1U) % MENU_ITEM_COUNT);
        }
    }

    if (menu_cursor == 0U) {
        if (key_edge(KEY_A) || key_edge(KEY_LEFT)) {
            selected_difficulty = (uint8_t)((selected_difficulty + DIFFICULTY_COUNT - 1U) % DIFFICULTY_COUNT);
        }
        if (key_edge(KEY_D) || key_edge(KEY_RIGHT)) {
            selected_difficulty = (uint8_t)((selected_difficulty + 1U) % DIFFICULTY_COUNT);
        }
    } else if (menu_cursor == 1U) {
        if (key_edge(KEY_A) || key_edge(KEY_LEFT) || key_edge(KEY_D) || key_edge(KEY_RIGHT)) {
            selected_players = (selected_players == 1U) ? 2U : 1U;
        }
    } else {
        if (key_edge(KEY_A) || key_edge(KEY_LEFT) || key_edge(KEY_D) || key_edge(KEY_RIGHT)) {
            selected_endless ^= 1U;
        }
    }

    if (key_edge(KEY_SPACE) || key_edge(KEY_Z) ||
        key_edge(KEY_ENTER) || key_edge(KEY_KP_ENTER)) {
        start_selected_game();
    }
}

static uint8_t spawn_player_bullet(int16_t x, int16_t y, int8_t vel_x, int8_t vel_y) {
    for (uint8_t i = 0U; i < MAX_PLAYER_BULLETS; i++) {
        if (player_bullets[i].visible == 0U) {
            player_bullets[i].x = x;
            player_bullets[i].y = y;
            player_bullets[i].visible = 1U;
            player_bullets[i].vel_x = vel_x;
            player_bullets[i].vel_y = vel_y;
            player_bullets[i].age = 0U;
            return 1U;
        }
    }
    return 0U;
}

static void fire_player_bullet(uint8_t player_index) {
    uint8_t fired = 0U;
    int8_t bullet_speed = (int8_t)difficulty()->player_bullet_speed;
    Sprite *shot_player;

    if (player_is_active(player_index) == 0U) {
        return;
    }
    shot_player = &players[player_index];

    if (focus_active != 0U) {
        fired |= spawn_player_bullet((int16_t)(shot_player->x + 10), (int16_t)(shot_player->y - 14), 0, (int8_t)(-bullet_speed - 1));
        fired |= spawn_player_bullet((int16_t)(shot_player->x + 20), (int16_t)(shot_player->y - 14), 0, (int8_t)(-bullet_speed - 1));
        fired |= spawn_player_bullet((int16_t)(shot_player->x + 15), (int16_t)(shot_player->y - 18), 0, (int8_t)(-bullet_speed - 2));
        (void)fired;
        return;
    }

    /* Weapon 2 is spread, weapon 3 is a faster homing/laser-looking shot. */
    if ((weapon_mode == 1U && power_level != 0U) || power_level >= 2U) {
        fired |= spawn_player_bullet((int16_t)(shot_player->x + 10), (int16_t)(shot_player->y - 12), -2, (int8_t)(1 - bullet_speed));
        fired |= spawn_player_bullet((int16_t)(shot_player->x + 20), (int16_t)(shot_player->y - 12), 2, (int8_t)(1 - bullet_speed));
    }
    if (power_level >= 3U) {
        fired |= spawn_player_bullet((int16_t)(shot_player->x + 4), (int16_t)(shot_player->y - 4), -3, (int8_t)(2 - bullet_speed));
        fired |= spawn_player_bullet((int16_t)(shot_player->x + 26), (int16_t)(shot_player->y - 4), 3, (int8_t)(2 - bullet_speed));
    }

    if (weapon_mode == 2U) {
        fired |= spawn_player_bullet((int16_t)(shot_player->x + 15), (int16_t)(shot_player->y - 15), 0, (int8_t)(-bullet_speed - 2));
    } else {
        fired |= spawn_player_bullet((int16_t)(shot_player->x + 15), (int16_t)(shot_player->y - 12), 0, (int8_t)-bullet_speed);
    }
    (void)fired;
}

static void spawn_powerup(int16_t x, int16_t y) {
    if (powerup.visible == 0U) {
        uint8_t kind = (uint8_t)(next_rand() % POWERUP_KIND_COUNT);

        /* Permanent drops grow firepower; timed drops create short speed/guard/score swings. */
        if (selected_difficulty == 0U && ((next_rand() & 0x3U) == 0U)) {
            kind = (uint8_t)(1U + (next_rand() % 3U));
        } else if (selected_difficulty == 2U && kind < 4U && ((next_rand() & 0x1U) != 0U)) {
            kind = (uint8_t)(4U + (next_rand() & 0x3U));
        } else if (selected_endless != 0U && stage > STAGE_COUNT && kind == 0U &&
                   fire_level < FIRE_LEVEL_MAX && ((next_rand() & 0x1U) != 0U)) {
            kind = 3U;
        }

        powerup.x = x;
        powerup.y = y;
        powerup.visible = 1U;
        powerup_kind = kind;
        powerup.sprite_type = powerup_sprite_for_kind(kind);
        powerup.frame = 0U;
        powerup.tint = 0U;
    }
}

static uint8_t spawn_enemy_shot(int16_t x, int16_t y, int8_t vx, int8_t vy) {
    for (uint8_t slot = 0U; slot < MAX_ENEMY_BULLETS; slot++) {
        if (enemy_bullets[slot].visible == 0U) {
            enemy_bullets[slot].x = x;
            enemy_bullets[slot].y = y;
            enemy_bullets[slot].visible = 1U;
            enemy_bullets[slot].vel_x = vx;
            enemy_bullets[slot].vel_y = vy;
            enemy_bullets[slot].age = 0U;
            return 1U;
        }
    }
    return 0U;
}

static void record_score_once(void) {
    if (score_recorded != 0U) {
        return;
    }
    score_recorded = 1U;

    for (uint8_t i = 0U; i < 5U; i++) {
        if (score > high_scores[i]) {
            for (uint8_t j = 4U; j > i; j--) {
                high_scores[j] = high_scores[j - 1U];
            }
            high_scores[i] = score;
            break;
        }
    }
}

static void fire_enemy_bullet(void) {
    uint8_t live_indices[NUM_ENEMIES];
    uint8_t live_count = 0U;

    for (uint8_t i = 0U; i < NUM_ENEMIES; i++) {
        if (enemies[i].visible != 0U && enemy_entry_ticks[i] == 0U) {
            live_indices[live_count++] = i;
        }
    }

    if (live_count == 0U) {
        return;
    }

    {
        uint8_t enemy_index = live_indices[next_rand() % live_count];
        int16_t sx = (int16_t)(enemies[enemy_index].x + 15);
        int16_t sy = (int16_t)(enemies[enemy_index].y + 30);
        Sprite *target = target_player_for_point(enemies[enemy_index].x, enemies[enemy_index].y);
        int16_t dx = (int16_t)(target->x - enemies[enemy_index].x);
        int8_t aim = (int8_t)clamp_i16((int16_t)(dx / 96), -2, 2);
        int8_t speed = (int8_t)scaled_enemy_bullet_speed();

        /* Touhou-like waves favor readable slow fans instead of fast enemy charges. */
        if (stage_pressure() >= 3U && (((frame_ticks >> 5) + enemy_index) % 4U) == 0U) {
            spawn_enemy_shot(sx, sy, (int8_t)(aim - 1), speed);
            spawn_enemy_shot(sx, sy, aim, speed);
            spawn_enemy_shot(sx, sy, (int8_t)(aim + 1), speed);
        } else if (stage_pressure() >= 5U && (((frame_ticks >> 6) + enemy_index) & 1U) != 0U) {
            static const int8_t burst_vx[6] = {0, 1, 2, 0, -2, -1};
            static const int8_t burst_vy[6] = {3, 3, 2, 4, 2, 3};
            for (uint8_t i = 0U; i < 6U; i++) {
                spawn_enemy_shot(sx, sy, burst_vx[(i + stage) % 6U],
                                 burst_vy[(i + stage) % 6U]);
            }
        } else {
            spawn_enemy_shot(sx, sy, aim, speed);
        }
    }
}

static void fire_boss_pattern(void) {
    static const int8_t ring_vx[16] = {0, 1, 2, 3, 3, 3, 2, 1, 0, -1, -2, -3, -3, -3, -2, -1};
    static const int8_t ring_vy[16] = {-3, -3, -2, -1, 0, 1, 2, 3, 3, 3, 2, 1, 0, -1, -2, -3};
    static const int8_t star_vx[12] = {0, 1, 2, 2, 1, 0, 0, -1, -2, -2, -1, 0};
    static const int8_t star_vy[12] = {3, 3, 2, 3, 4, 5, 3, 3, 2, 3, 4, 5};
    uint8_t phase;

    if (boss.visible == 0U || boss_entry_ticks != 0U) {
        return;
    }

    phase = (uint8_t)((frame_ticks >> 2) & 0xFU);
    if (((frame_ticks >> 6) & 1U) != 0U) {
        uint8_t step = boss_kind == 0U ? 4U : (boss_kind == 1U ? 3U : 2U);
        for (uint8_t i = 0U; i < 16U; i = (uint8_t)(i + step)) {
            uint8_t p = (uint8_t)((i + phase) & 0xFU);
            spawn_enemy_shot((int16_t)(boss.x + 30), (int16_t)(boss.y + 34),
                             ring_vx[p], (int8_t)(ring_vy[p] + 2));
        }
    } else {
        uint8_t fan_count = (uint8_t)(5U + boss_kind * 2U);
        for (uint8_t n = 0U; n < fan_count; n++) {
            int8_t spread = (int8_t)((int8_t)n - (int8_t)(fan_count / 2U));
            Sprite *target = target_player_for_point(boss.x, boss.y);
            spawn_enemy_shot((int16_t)(boss.x + 28 + spread * 8), (int16_t)(boss.y + 56),
                             (int8_t)(spread + clamp_i16((int16_t)((target->x - boss.x) / 128), -1, 1)),
                             (int8_t)clamp_i16((int16_t)(scaled_enemy_bullet_speed() + 1), 3, 6));
        }
    }

    if (stage_pressure() >= 3U) {
        uint8_t offset = (uint8_t)((frame_ticks >> 3) % 12U);
        for (uint8_t i = 0U; i < 12U; i = (uint8_t)(i + 3U)) {
            uint8_t p = (uint8_t)((i + offset) % 12U);
            spawn_enemy_shot((int16_t)(boss.x + 30), (int16_t)(boss.y + 42),
                             star_vx[p], star_vy[p]);
        }
    }
}

static void respawn_boss_escorts(void) {
    uint8_t live_count;
    uint8_t target;
    uint8_t spawn_limit;
    uint8_t spawned = 0U;

    if (boss.visible == 0U || ready_ticks != 0U || boss_entry_ticks != 0U) {
        return;
    }

    live_count = live_enemy_count();
    target = configured_escort_target();
    if (target == 0U || live_count >= target) {
        return;
    }
    if ((frame_ticks % scaled_period(180U)) != 0U) {
        return;
    }

    spawn_limit = configured_escort_spawn_count();
    if (spawn_limit > 1U) {
        spawn_limit = 1U;
    }
    /* Boss escorts refill slowly and use spacing checks so enemies do not stack visually. */
    while (spawned < spawn_limit && (uint8_t)(live_count + spawned) < target) {
        uint8_t placed = 0U;

        for (uint8_t i = 0U; i < NUM_ENEMIES; i++) {
            if (enemies[i].visible == 0U) {
                int16_t x;
                int16_t y;
                if (find_clear_enemy_position(&x, &y, i,
                                              (uint8_t)((spawned + stage) % NUM_ENEMY_ROWS),
                                              (uint8_t)(next_rand() % NUM_ENEMY_COLS)) != 0U) {
                    set_enemy_slot(i, x, y, (uint8_t)((spawned + 1U) % NUM_ENEMY_ROWS),
                                   (uint8_t)(next_rand() + boss_kind));
                    placed = 1U;
                }
                break;
            }
        }
        if (placed == 0U) {
            break;
        }
        spawned++;
    }
}

static void separate_enemy_from_previous(uint8_t index) {
    for (uint8_t other = 0U; other < index; other++) {
        if (enemies[other].visible != 0U &&
            abs_i16((int16_t)(enemies[index].x - enemies[other].x)) < ENEMY_RENDER_MIN_DX &&
            abs_i16((int16_t)(enemies[index].y - enemies[other].y)) < ENEMY_RENDER_MIN_DY) {
            int16_t dir = enemies[index].x >= enemies[other].x ? 1 : -1;
            int16_t candidate_x = (int16_t)(enemies[other].x + dir * ENEMY_RENDER_MIN_DX);

            if (candidate_x < PLAYFIELD_LEFT || candidate_x > (int16_t)(PLAYFIELD_RIGHT - 32)) {
                candidate_x = (int16_t)(enemies[other].x - dir * ENEMY_RENDER_MIN_DX);
            }
            enemies[index].x = clamp_i16(candidate_x, PLAYFIELD_LEFT, (int16_t)(PLAYFIELD_RIGHT - 32));
            if (abs_i16((int16_t)(enemies[index].x - enemies[other].x)) < ENEMY_RENDER_MIN_DX) {
                enemies[index].y = clamp_i16((int16_t)(enemies[other].y + ENEMY_RENDER_MIN_DY),
                                             32, (int16_t)(PLAYER_START_Y - 40));
            }
        }
    }
}

static int16_t enemy_ai_offset(uint8_t index, uint16_t seed) {
    int16_t pressure = (int16_t)stage_pressure();
    Sprite *target = target_player_for_point(enemy_home_x[index], enemy_home_y[index]);
    int16_t player_center = (int16_t)(target->x + 15);
    int16_t enemy_center = (int16_t)(enemy_home_x[index] + 15);
    int16_t dx = (int16_t)(player_center - enemy_center);
    int16_t chase = clamp_i16((int16_t)(dx / (8 + (seed & 0x7U))),
                              (int16_t)(-34 - pressure * 4),
                              (int16_t)(34 + pressure * 4));
    int16_t sway = (int16_t)(wave16((frame_ticks >> 2) + seed * 5U + index * 11U) *
                             (1 + pressure / 3));

    switch ((uint8_t)((seed + index + stage) & 0x3U)) {
        case 0U:
            return (int16_t)(chase + sway);
        case 1U:
            return (int16_t)(chase / 2 + ((index & 1U) != 0U ? 26 : -26) + sway / 2);
        case 2U:
            if (target->y > enemies[index].y && abs_i16(dx) < 58) {
                int16_t dodge = dx >= 0 ? (int16_t)(-30 - pressure * 2) : (int16_t)(30 + pressure * 2);
                return (int16_t)(dodge + chase / 3);
            }
            return (int16_t)(chase / 3 + sway);
        default:
            return (int16_t)(chase / 2 - sway / 2);
    }
}

static void update_enemies(void) {
    const StageConfig *cfg = &stage_config[stage_index()];
    uint16_t fall_period = scaled_period(cfg->fall_period);

    if (fall_period < 78U) {
        fall_period = 78U;
    }

    if ((frame_ticks % 128U) == 0U) {
        enemy_dir = (int8_t)-enemy_dir;
    }

    respawn_boss_escorts();

    if (enemy_spawn_cursor < enemy_spawn_target &&
        (frame_ticks % scaled_period(54U)) == 0U &&
        spawn_sequence_enemy(enemy_spawn_cursor) != 0U) {
        enemy_spawn_cursor++;
    }

    for (uint8_t i = 0U; i < NUM_ENEMIES; i++) {
        if (enemies[i].visible != 0U) {
            uint16_t seed = g_enemy_wave_seed[i % g_enemy_wave_seed_count];
            /* Seeded triangle waves give each enemy a slow spell-card drift. */
            int16_t wave = (int16_t)(wave16((frame_ticks >> 2) + seed) * (5 + stage_pressure()) / 5);
            uint16_t dive_period = scaled_period(cfg->dive_period);
            uint16_t dive_phase = (uint16_t)((frame_ticks + seed * 3U) % dive_period);
            int16_t dive = 0;

            if (enemy_entry_ticks[i] != 0U) {
                int16_t entry_step = (int16_t)(3 + stage_pressure() / 5U);

                enemies[i].x = move_towards_i16(enemies[i].x, enemy_home_x[i], entry_step);
                enemies[i].y = move_towards_i16(enemies[i].y, enemy_home_y[i], entry_step);
                if (enemies[i].x == enemy_home_x[i] && enemies[i].y == enemy_home_y[i]) {
                    enemy_entry_ticks[i] = 0U;
                } else {
                    enemy_entry_ticks[i] = enemy_entry_ticks[i] > 1U ?
                                           (uint8_t)(enemy_entry_ticks[i] - 1U) : 1U;
                }
                if ((frame_ticks & 0x7U) == 0U) {
                    enemies[i].frame = (uint8_t)((enemies[i].frame + 1U) & 0x3U);
                }
                continue;
            }

            if ((frame_ticks % fall_period) == 0U) {
                enemy_home_y[i] = (int16_t)(enemy_home_y[i] + 3 + stage_pressure() / 2U);
            }

            if (dive_phase < 80U) {
                dive = (int16_t)(dive_phase / 5U + stage_pressure());
            } else if (stage >= 3U && dive_phase > (dive_period - 64U)) {
                dive = (int16_t)((dive_period - dive_phase) / 5U + stage_pressure());
            }

            enemies[i].x = clamp_i16((int16_t)(enemy_home_x[i] + enemy_dir * wave +
                                               enemy_ai_offset(i, seed)),
                                     PLAYFIELD_LEFT, (int16_t)(PLAYFIELD_RIGHT - 32));
            enemies[i].y = (int16_t)(enemy_home_y[i] + dive);
            separate_enemy_from_previous(i);
            if ((frame_ticks & 0x7U) == 0U) {
                enemies[i].frame = (uint8_t)((enemies[i].frame + 1U) & 0x3U);
            }

            if (enemies[i].y >= lowest_active_player_y() - 20) {
                enemies[i].visible = 0U;
                enemy_hp[i] = 0U;
                spawn_explosion(enemies[i].x, enemies[i].y);
                apply_player_damage_to(target_player_index_for_point(enemies[i].x, enemies[i].y),
                                       difficulty()->enemy_hit_damage);
            }
        }
    }

    if (boss.visible != 0U) {
        if (boss_entry_ticks != 0U) {
            boss.x = move_towards_i16(boss.x, boss_home_x, 3);
            boss.y = move_towards_i16(boss.y, boss_home_y, 3);
            if (boss.x == boss_home_x && boss.y == boss_home_y) {
                boss_entry_ticks = 0U;
            } else {
                boss_entry_ticks = boss_entry_ticks > 1U ?
                                   (uint8_t)(boss_entry_ticks - 1U) : 1U;
            }
        } else {
            boss.x = clamp_i16((int16_t)(boss_home_x + wave16((frame_ticks >> 2) + stage * 9U) * (2 + boss_kind)),
                               PLAYFIELD_LEFT, (int16_t)(PLAYFIELD_RIGHT - 70));
            boss.y = (int16_t)(boss_home_y + wave16((frame_ticks >> 2) + stage * 7U) / 5);
        }
        if ((frame_ticks & 0x7U) == 0U) {
            boss.frame = (uint8_t)((boss.frame + 1U) & 0xFU);
        }
    }
}

static void update_bullets(void) {
    for (uint8_t i = 0U; i < MAX_PLAYER_BULLETS; i++) {
        if (player_bullets[i].visible != 0U) {
            if (weapon_mode == 2U && (player_bullets[i].age & 0x3U) == 0U) {
                int16_t best_dx = 32767;
                /* Homing shots only make small steering steps so they still feel fair. */
                for (uint8_t enemy = 0U; enemy < NUM_ENEMIES; enemy++) {
                    if (enemies[enemy].visible != 0U && enemies[enemy].y < player_bullets[i].y) {
                        int16_t dx = (int16_t)((enemies[enemy].x + 8) - player_bullets[i].x);
                        int16_t adx = dx >= 0 ? dx : (int16_t)-dx;
                        if (adx < best_dx) {
                            best_dx = adx;
                            if (dx > 4) {
                                player_bullets[i].vel_x = 1;
                            } else if (dx < -4) {
                                player_bullets[i].vel_x = -1;
                            }
                        }
                    }
                }
            }
            player_bullets[i].x = (int16_t)(player_bullets[i].x + player_bullets[i].vel_x);
            player_bullets[i].y = (int16_t)(player_bullets[i].y + player_bullets[i].vel_y);
            player_bullets[i].age++;
            if (player_bullets[i].y < -16 || player_bullets[i].x < PLAYFIELD_LEFT ||
                player_bullets[i].x > PLAYFIELD_RIGHT) {
                player_bullets[i].visible = 0U;
            }
        }
    }

    for (uint8_t i = 0U; i < MAX_ENEMY_BULLETS; i++) {
        if (enemy_bullets[i].visible != 0U) {
            enemy_bullets[i].x = (int16_t)(enemy_bullets[i].x + enemy_bullets[i].vel_x);
            enemy_bullets[i].y = (int16_t)(enemy_bullets[i].y + enemy_bullets[i].vel_y);
            enemy_bullets[i].age++;
            if (enemy_bullets[i].y > 480 || enemy_bullets[i].x < PLAYFIELD_LEFT ||
                enemy_bullets[i].x > PLAYFIELD_RIGHT) {
                enemy_bullets[i].visible = 0U;
            }
        }
    }
}

static void update_powerup(void) {
    if (powerup.visible == 0U) {
        return;
    }

    powerup.y = (int16_t)(powerup.y + 2);
    powerup.frame = (uint8_t)((powerup.frame + 1U) & 0xFU);
    if (powerup.y > 480) {
        powerup.visible = 0U;
        return;
    }

    for (uint8_t player_index = 0U; player_index < active_player_count(); player_index++) {
        if (player_is_active(player_index) == 0U ||
            boxes_overlap(powerup.x, powerup.y, 28, 28,
                          (int16_t)(players[player_index].x + PLAYER_PICKUP_X),
                          (int16_t)(players[player_index].y + PLAYER_PICKUP_Y),
                          PLAYER_PICKUP_W, PLAYER_PICKUP_H) == 0U) {
            continue;
        }
        powerup.visible = 0U;
        /* Permanent drops upgrade fire mode/rate/damage; timed drops are utility tools. */
        if (powerup_kind == 0U) {
            shield = shield < SHIELD_MAX ? (uint8_t)(shield + 1U) : shield;
        } else if (powerup_kind == 1U) {
            weapon_mode = (uint8_t)((weapon_mode + 1U) % 3U);
        } else if (powerup_kind == 2U) {
            power_level = power_level < POWER_LEVEL_MAX ? (uint8_t)(power_level + 1U) : power_level;
        } else if (powerup_kind == 3U) {
            fire_level = fire_level < FIRE_LEVEL_MAX ? (uint8_t)(fire_level + 1U) : fire_level;
        } else if (powerup_kind == 4U) {
            speed_ticks = timed_powerup_duration();
        } else if (powerup_kind == 5U) {
            barrier_ticks = timed_powerup_duration();
            clear_enemy_bullets();
        } else if (powerup_kind == 6U) {
            score_boost_ticks = timed_powerup_duration();
        } else {
            clear_enemy_bullets();
            for (uint8_t enemy = 0U; enemy < NUM_ENEMIES; enemy++) {
                if (enemies[enemy].visible != 0U) {
                    enemies[enemy].visible = 0U;
                    spawn_explosion(enemies[enemy].x, enemies[enemy].y);
                    add_score((uint32_t)(20U + stage_pressure() * 4U));
                }
            }
            if (boss.visible != 0U) {
                uint16_t damage = (uint16_t)(8U + stage_pressure() * 2U);
                boss_hp = (boss_hp > damage) ? (uint16_t)(boss_hp - damage) : 0U;
                if (boss_hp == 0U) {
                    boss.visible = 0U;
                    spawn_explosion((int16_t)(boss.x + 20), (int16_t)(boss.y + 20));
                }
            }
        }
        if (powerup_kind == 0U && shield == SHIELD_MAX && lives < 9U && selected_difficulty == 0U &&
            ((next_rand() & 0x3FU) == 0U)) {
            lives++;
        }
        point_items = point_items < 999U ? (uint16_t)(point_items + 1U) : point_items;
        add_score(100UL);
        audio_engine_play_stage_clear();
        break;
    }
}

static void clear_enemy_bullets(void) {
    for (uint8_t i = 0U; i < MAX_ENEMY_BULLETS; i++) {
        enemy_bullets[i].visible = 0U;
    }
}

static void respawn_player_after_hit(uint8_t player_index) {
    if (player_index >= active_player_count()) {
        player_index = 0U;
    }
    players[player_index].x = player_start_x(player_index);
    players[player_index].y = PLAYER_START_Y;
    players[player_index].visible = 1U;
    invincible_ticks = 96U;
    focus_active = 0U;
    clear_enemy_bullets();
    spawn_explosion(players[player_index].x, players[player_index].y);
    audio_engine_play_player_hit();
}

static void apply_player_damage_to(uint8_t player_index, uint8_t damage) {
    uint8_t remaining = damage == 0U ? 1U : damage;

    if (barrier_ticks != 0U) {
        add_score(5UL);
        return;
    }
    if (invincible_ticks != 0U) {
        return;
    }

    while (remaining != 0U && shield != 0U) {
        shield--;
        remaining--;
    }
    while (remaining != 0U && shield == 0U && lives != 0U) {
        lives--;
        remaining--;
    }

    if (lives == 0U && shield == 0U) {
        game_state = GAME_OVER;
        game_over_ticks = GAME_OVER_RESTART_TICKS;
        record_score_once();
    }

    respawn_player_after_hit(player_index);
}


static void update_explosions(void) {
    for (uint8_t i = 0U; i < MAX_EXPLOSIONS; i++) {
        if (explosions[i].visible != 0U) {
            if (explosions[i].ttl == 0U) {
                explosions[i].visible = 0U;
            } else {
                explosions[i].ttl--;
                if ((frame_ticks & 0x3U) == 0U) {
                    explosions[i].frame++;
                }
            }
        }
    }
}

static void handle_collisions(void) {
    for (uint8_t bullet = 0U; bullet < MAX_PLAYER_BULLETS; bullet++) {
        if (player_bullets[bullet].visible == 0U) {
            continue;
        }
        for (uint8_t enemy = 0U; enemy < NUM_ENEMIES; enemy++) {
            if (enemies[enemy].visible != 0U &&
                boxes_overlap(player_bullets[bullet].x, player_bullets[bullet].y, 4, 12,
                              enemies[enemy].x, enemies[enemy].y, 30, 30)) {
                player_bullets[bullet].visible = 0U;
                if (enemy_hp[enemy] > player_damage_amount()) {
                    enemy_hp[enemy] = (uint8_t)(enemy_hp[enemy] - player_damage_amount());
                    add_score(2UL);
                } else {
                    uint16_t base_score = (uint16_t)(10U + (enemy / NUM_ENEMY_COLS) * 5U +
                                                     enemy_hp[enemy] * 3U);
                    enemies[enemy].visible = 0U;
                    enemy_hp[enemy] = 0U;
                    /* Rows are worth different base scores; quick kills extend combo bonus. */
                    combo = combo_timer != 0U ? (uint16_t)(combo + 1U) : 1U;
                    combo_timer = 90U;
                    add_score((uint32_t)base_score * stage + (uint32_t)combo * 2UL);
                    point_items = point_items < 999U ? (uint16_t)(point_items + 1U) : point_items;
                    spawn_explosion(enemies[enemy].x, enemies[enemy].y);
                    if ((next_rand() & powerup_drop_mask()) == 0U) {
                        spawn_powerup(enemies[enemy].x, enemies[enemy].y);
                    }
                    audio_engine_play_explosion();
                }
                break;
            }
        }
    }

    if (boss.visible != 0U) {
        for (uint8_t bullet = 0U; bullet < MAX_PLAYER_BULLETS; bullet++) {
            if (player_bullets[bullet].visible != 0U &&
                boxes_overlap(player_bullets[bullet].x, player_bullets[bullet].y, 4, 12,
                              boss.x, boss.y, 62, 62)) {
                player_bullets[bullet].visible = 0U;
                if (boss_hp > 0U) {
                    uint8_t damage = player_damage_amount();
                    boss_hp = boss_hp > damage ? (uint16_t)(boss_hp - damage) : 0U;
                }
                combo = combo_timer != 0U ? (uint16_t)(combo + 1U) : 1U;
                combo_timer = 90U;
                add_score(5UL + (uint32_t)combo);
                if (boss_hp == 0U) {
                    boss.visible = 0U;
                    spawn_explosion((int16_t)(boss.x + 20), (int16_t)(boss.y + 20));
                    spawn_powerup((int16_t)(boss.x + 24), (int16_t)(boss.y + 32));
                    point_items = point_items < 995U ? (uint16_t)(point_items + 5U) : point_items;
                    add_score((uint32_t)(500U + stage_pressure() * 100U + boss_kind * 250U));
                    audio_engine_play_explosion();
                }
            }
        }
    }

    if (power_level != 0U) {
        uint8_t orbit_count = power_level >= 2U ? 8U : 4U;
        for (uint8_t i = 0U; i < orbit_count; i++) {
            uint32_t phase = frame_ticks + i * (64U / orbit_count);
            int16_t ox = (int16_t)(player.x + 8 + wave16(phase) * 2);
            int16_t oy = (int16_t)(player.y + 8 + wave16(phase + 16U) * 2);

            for (uint8_t enemy = 0U; enemy < NUM_ENEMIES; enemy++) {
                if (enemies[enemy].visible != 0U &&
                    boxes_overlap(ox, oy, 12, 12, enemies[enemy].x, enemies[enemy].y, 30, 30)) {
                    uint8_t damage = (uint8_t)clamp_i16((int16_t)player_damage_amount() - 1, 1, 4);
                    if (enemy_hp[enemy] > damage) {
                        enemy_hp[enemy] = (uint8_t)(enemy_hp[enemy] - damage);
                    } else {
                        enemies[enemy].visible = 0U;
                        enemy_hp[enemy] = 0U;
                        spawn_explosion(enemies[enemy].x, enemies[enemy].y);
                        add_score((uint32_t)(20U + combo));
                        combo = combo_timer != 0U ? (uint16_t)(combo + 1U) : 1U;
                        combo_timer = 90U;
                        audio_engine_play_explosion();
                    }
                }
            }

            if (boss.visible != 0U && boxes_overlap(ox, oy, 12, 12, boss.x, boss.y, 62, 62)) {
                if ((frame_ticks & 0x3U) == 0U && boss_hp > 0U) {
                    uint8_t damage = (uint8_t)clamp_i16((int16_t)player_damage_amount() - 1, 1, 4);
                    boss_hp = boss_hp > damage ? (uint16_t)(boss_hp - damage) : 0U;
                    add_score(3UL);
                    if (boss_hp == 0U) {
                        boss.visible = 0U;
                        spawn_explosion((int16_t)(boss.x + 20), (int16_t)(boss.y + 20));
                        spawn_powerup((int16_t)(boss.x + 24), (int16_t)(boss.y + 32));
                        point_items = point_items < 995U ? (uint16_t)(point_items + 5U) : point_items;
                        add_score((uint32_t)(500U + stage_pressure() * 100U + boss_kind * 250U));
                        audio_engine_play_explosion();
                    }
                }
            }
        }
    }

    for (uint8_t i = 0U; i < MAX_ENEMY_BULLETS; i++) {
        if (enemy_bullets[i].visible == 0U) {
            continue;
        }
        for (uint8_t player_index = 0U; player_index < active_player_count(); player_index++) {
            if (player_is_active(player_index) == 0U ||
                boxes_overlap(enemy_bullets[i].x, enemy_bullets[i].y, 4, 12,
                              (int16_t)(players[player_index].x + PLAYER_HITBOX_X),
                              (int16_t)(players[player_index].y + PLAYER_HITBOX_Y),
                              PLAYER_HITBOX_W, PLAYER_HITBOX_H) == 0U) {
                continue;
            }
            enemy_bullets[i].visible = 0U;
            if (barrier_ticks != 0U) {
                add_score(5UL);
                break;
            }
            if (invincible_ticks != 0U) {
                break;
            }
            add_score(shield != 0U ? 25UL : 0UL);
            apply_player_damage_to(player_index, difficulty()->enemy_hit_damage);
            break;
        }
    }
}

static void advance_stage_if_clear(void) {
    if (boss.visible != 0U) {
        return;
    }
    if (enemy_spawn_cursor < enemy_spawn_target) {
        return;
    }

    for (uint8_t i = 0U; i < NUM_ENEMIES; i++) {
        if (enemies[i].visible != 0U) {
            return;
        }
    }

    stage++;
    if (stage > STAGE_COUNT && selected_endless == 0U) {
        game_state = WIN;
        record_score_once();
        audio_engine_play_stage_clear();
        return;
    }

    /* Wave transitions never stall the playfield; old bullets drain while the next wave enters. */
    enemy_dir = 1;
    shield = shield < SHIELD_MAX ? (uint8_t)(shield + 1U) : shield;
    ready_ticks = READY_STAGE_TICKS;
    stage_timer = stage_config[stage_index()].time_limit;
    combo = 0U;
    combo_timer = 0U;
    spawn_enemies();
    audio_engine_play_stage_clear();
}

static void update_player_movement(uint8_t player_index) {
    uint8_t use_shared_keys = (active_player_count() == 1U) ? 1U : 0U;
    uint8_t left = 0U;
    uint8_t right = 0U;
    uint8_t up = 0U;
    uint8_t down = 0U;
    Sprite *moving_player;

    if (player_is_active(player_index) == 0U) {
        return;
    }

    if (use_shared_keys != 0U || player_index == 0U) {
        left |= get_key_pressed(KEY_A);
        right |= get_key_pressed(KEY_D);
        up |= get_key_pressed(KEY_W);
        down |= get_key_pressed(KEY_S);
    }
    if (use_shared_keys != 0U || player_index == 1U) {
        left |= get_key_pressed(KEY_LEFT);
        right |= get_key_pressed(KEY_RIGHT);
        up |= get_key_pressed(KEY_UP);
        down |= get_key_pressed(KEY_DOWN);
    }

    moving_player = &players[player_index];
    if (left != 0U && moving_player->x > PLAYER_MIN_X) {
        moving_player->x = (int16_t)(moving_player->x - player_move_speed());
    }
    if (right != 0U && moving_player->x < PLAYER_MAX_X) {
        moving_player->x = (int16_t)(moving_player->x + player_move_speed());
    }
    if (up != 0U && moving_player->y > PLAYER_MIN_Y) {
        moving_player->y = (int16_t)(moving_player->y - player_move_speed());
    }
    if (down != 0U && moving_player->y < PLAYER_MAX_Y) {
        moving_player->y = (int16_t)(moving_player->y + player_move_speed());
    }
    moving_player->x = clamp_i16(moving_player->x, PLAYER_MIN_X, PLAYER_MAX_X);
    moving_player->y = clamp_i16(moving_player->y, PLAYER_MIN_Y, PLAYER_MAX_Y);
}

void update_game(void) {
    if (game_state == WAITING_START) {
        update_menu();
        return;
    }

    if (game_state == GAME_OVER) {
        frame_ticks++;
        if (game_over_ticks != 0U) {
            game_over_ticks--;
        } else {
            start_selected_game();
        }
        return;
    }

    if (game_state != PLAYING) {
        return;
    }

    frame_ticks++;
    for (uint8_t i = 0U; i < active_player_count(); i++) {
        players[i].frame = (uint8_t)(((frame_ticks >> 2) + i * 3U) & 0xFU);
    }
    if (combo_timer != 0U) {
        combo_timer--;
        if (combo_timer == 0U) {
            combo = 0U;
        }
    }
    if (invincible_ticks != 0U) {
        invincible_ticks--;
    }
    if (speed_ticks != 0U) {
        speed_ticks--;
    }
    if (barrier_ticks != 0U) {
        barrier_ticks--;
    }
    if (score_boost_ticks != 0U) {
        score_boost_ticks--;
    }
    if (stage_timer != 0U) {
        stage_timer--;
    }
    focus_active = (uint8_t)(get_key_pressed(KEY_X) != 0U);
    if (key_edge(KEY_Z) && shield != 0U) {
        shield--;
        barrier_ticks = 90U;
        clear_enemy_bullets();
        for (uint8_t enemy = 0U; enemy < NUM_ENEMIES; enemy++) {
            if (enemies[enemy].visible != 0U) {
                enemies[enemy].visible = 0U;
                enemy_hp[enemy] = 0U;
                spawn_explosion(enemies[enemy].x, enemies[enemy].y);
                add_score(30UL);
            }
        }
        if (boss.visible != 0U && boss_hp > 0U) {
            uint16_t damage = (uint16_t)(18U + stage_pressure() * 4U);
            boss_hp = boss_hp > damage ? (uint16_t)(boss_hp - damage) : 0U;
            if (boss_hp == 0U) {
                boss.visible = 0U;
                spawn_explosion((int16_t)(boss.x + 20), (int16_t)(boss.y + 20));
            }
        }
        audio_engine_play_stage_clear();
    }

    for (uint8_t i = 0U; i < active_player_count(); i++) {
        update_player_movement(i);
    }

    {
        uint8_t fire_interval = player_fire_interval();
        if ((frame_ticks % fire_interval) == 1U) {
            for (uint8_t i = 0U; i < active_player_count(); i++) {
                fire_player_bullet(i);
            }
        }
    }

    if (ready_ticks != 0U) {
        ready_ticks--;
    }

#ifdef MB_NO_USB
    if (powerup.visible == 0U && (frame_ticks % 540U) == 120U) {
        /* Autonomous board demos need periodic drops so pickup logic is exercised on camera. */
        spawn_powerup(clamp_i16((int16_t)(player.x + wave16(frame_ticks) * 2),
                                PLAYFIELD_LEFT, (int16_t)(PLAYFIELD_RIGHT - 32)),
                      96);
    }
#endif

    update_powerup();
    update_enemies();
    update_bullets();
    update_explosions();

    if ((frame_ticks % scaled_period(stage_config[stage_index()].fire_period)) == 0U) {
        fire_enemy_bullet();
    }
    if (boss.visible != 0U && (frame_ticks % scaled_period((uint16_t)(52U - boss_kind * 4U))) == 0U) {
        fire_boss_pattern();
    }

    handle_collisions();
    for (uint8_t i = 0U; i < MAX_ENEMY_BULLETS; i++) {
        /* Graze reward: near misses remove the bullet and add a small score bonus. */
        if (enemy_bullets[i].visible == 0U) {
            continue;
        }
        for (uint8_t player_index = 0U; player_index < active_player_count(); player_index++) {
            if (player_is_active(player_index) != 0U &&
                boxes_overlap(enemy_bullets[i].x, enemy_bullets[i].y, 10, 14,
                              (int16_t)(players[player_index].x - 10),
                              (int16_t)(players[player_index].y - 10), 36, 36) != 0U &&
                boxes_overlap(enemy_bullets[i].x, enemy_bullets[i].y, 4, 12,
                              (int16_t)(players[player_index].x + PLAYER_HITBOX_X),
                              (int16_t)(players[player_index].y + PLAYER_HITBOX_Y),
                              PLAYER_HITBOX_W, PLAYER_HITBOX_H) == 0U) {
                if ((enemy_bullets[i].age & 0x7U) == 0U) {
                    graze_score++;
                    add_score(2UL);
                }
                break;
            }
        }
    }
    advance_stage_if_clear();
}

static void render_menu_screen(void) {
    char diff_str[17];
    char players_str[17];
    char mode_str[17];
    uint8_t diff_color = (menu_cursor == 0U) ? 0xEU : 0xFU;
    uint8_t players_color = (menu_cursor == 1U) ? 0xEU : 0xFU;
    uint8_t mode_color = (menu_cursor == 2U) ? 0xEU : 0xFU;
    int16_t ship_bob = (int16_t)(wave16(frame_ticks >> 1) / 4);
    uint8_t title_color = ((frame_ticks >> 4) & 1U) ? 0xFU : 0x9U;

    text_join(diff_str, "DIFF ", difficulty()->name);
    text_join(players_str, selected_players == 1U ? "ONE" : "TWO", " PLAYER");
    text_copy(mode_str, selected_endless != 0U ? "ENDLESS" : "ARCADE");

    hdmi_text_controller_clear_sprites();
    hdmi_text_controller_clear_text();

    hdmi_text_controller_set_sprite(0U, 112, (int16_t)(344 + ship_bob), SPR_PLAYER_LARGE,
                                    (uint8_t)(frame_ticks >> 2), 1U, selected_difficulty);
    for (uint8_t i = 0U; i < 7U; i++) {
        int16_t enemy_bob = (int16_t)(wave16((frame_ticks >> 1) + i * 9U) / 5);
        hdmi_text_controller_set_sprite((uint8_t)(1U + i), (int16_t)(54 + i * 54),
                                        (int16_t)(150 + enemy_bob + ((i & 1U) ? 18 : 0)),
                                        (uint8_t)(SPR_ENEMY_WING_LARGE + (i % 3U)), (uint8_t)(frame_ticks >> 3),
                                        1U, (uint8_t)(i & 0x3U));
    }
    for (uint8_t i = 0U; i < 12U; i++) {
        int16_t shot_y = (int16_t)(118 + ((frame_ticks * (2U + (i & 1U)) + i * 31U) % 210U));
        int16_t shot_x = (int16_t)(34 + i * 34 + (wave16((frame_ticks >> 2) + i * 11U) / 7));
        hdmi_text_controller_set_sprite((uint8_t)(60U + i), shot_x, shot_y,
                                        (i & 3U) == 0U ? SPR_ENEMY_RING_BULLET : ((i & 1U) ? 5U : SPR_ENEMY_SHARD_BULLET),
                                        (uint8_t)(frame_ticks >> 2), 1U,
                                        (uint8_t)((i + selected_difficulty) & 0x3U));
    }
    for (uint8_t i = 0U; i < 6U; i++) {
        int16_t orbit_x = (int16_t)(60 + i * 42 + wave16((frame_ticks >> 1) + i * 13U) / 6);
        int16_t orbit_y = (int16_t)(352 + wave16((frame_ticks >> 1) + i * 17U) / 7);
        hdmi_text_controller_set_sprite((uint8_t)(72U + i), orbit_x, orbit_y,
                                        SPR_OPTION_ORB, (uint8_t)(frame_ticks >> 3),
                                        1U, (uint8_t)(i & 0x3U));
    }

    hdmi_text_controller_set_text_at(0U, 46U, 44U, "IN 6B BORDER", title_color);
    hdmi_text_controller_set_text_at(1U, 46U, 78U, "ENDLESS NIGHT", 0x9U);
    hdmi_text_controller_set_text_at(2U, 328U, 134U, "PRESS START", 0xAU);
    hdmi_text_controller_set_text_at(3U, 328U, 184U, diff_str, diff_color);
    hdmi_text_controller_set_text_at(4U, 328U, 222U, players_str, players_color);
    hdmi_text_controller_set_text_at(5U, 328U, 260U, mode_str, mode_color);
    hdmi_text_controller_set_text_at(6U, 328U, 324U, "W S SELECT", 0xCU);
    hdmi_text_controller_set_text_at(7U, 328U, 352U, "A D CHANGE", 0xCU);
    hdmi_text_controller_set_text_at(8U, 328U, 388U, "SPACE START", 0xEU);
    hdmi_text_controller_set_text_at(9U, HUD_TEXT_X, 62U, "RANKING", 0xCU);
    for (uint8_t i = 0U; i < 5U; i++) {
        char rank_str[17];
        text_rank(rank_str, (uint8_t)(i + 1U), high_scores[i]);
        hdmi_text_controller_set_text_at((uint8_t)(10U + i), HUD_TEXT_X,
                                         (uint16_t)(96U + i * 26U), rank_str,
                                         i == 0U ? 0xEU : 0xCU);
    }
    hdmi_text_controller_set_text_at(15U, HUD_TEXT_X, 242U, selected_endless != 0U ? "NO LIMIT" : "6 STAGES", 0x6U);
}

void render_game(void) {
    char score_str[17];
    char lives_str[17];
    char stage_str[17];
    char shield_str[17];
    char graze_str[17];
    char point_str[17];
    char time_str[17];
    char spell_str[17];
    const char *stage_name;
    const char *boss_title;
    uint8_t player_visible = player.visible;
    uint8_t player_tint = weapon_mode & 0x3U;

    if (game_state == WAITING_START) {
        render_menu_screen();
        return;
    }

    if (invincible_ticks != 0U) {
        /* Damage feedback uses both tint and sprite blinking. */
        player_tint = 3U;
        if ((invincible_ticks & 0x4U) == 0U) {
            player_visible = 0U;
        }
    } else if (focus_active != 0U) {
        player_tint = 2U;
    }

    /* Slot layout mirrors game.h so software never exceeds the hardware sprite table. */
    hdmi_text_controller_set_sprite(0U, player.x, player.y, player.sprite_type, player.frame,
                                    player_visible, player_tint);
    if (active_player_count() == 2U) {
        uint8_t player2_visible = players[1].visible;
        uint8_t player2_tint = (uint8_t)((weapon_mode + 1U) & 0x3U);

        if (invincible_ticks != 0U) {
            player2_tint = 3U;
            if ((invincible_ticks & 0x4U) == 0U) {
                player2_visible = 0U;
            }
        } else if (focus_active != 0U) {
            player2_tint = 2U;
        }
        hdmi_text_controller_set_sprite(PLAYER2_SPRITE_SLOT, players[1].x, players[1].y,
                                        players[1].sprite_type, players[1].frame,
                                        player2_visible, player2_tint);
    }

    for (uint8_t i = 0U; i < NUM_ENEMIES; i++) {
        hdmi_text_controller_set_sprite((uint8_t)(1U + i), enemies[i].x, enemies[i].y,
                                        enemies[i].sprite_type, enemies[i].frame,
                                        enemies[i].visible, enemies[i].tint);
    }

    for (uint8_t i = 0U; i < MAX_PLAYER_BULLETS; i++) {
        uint8_t player_bullet_type = weapon_mode == 2U ? 8U :
                                     ((player_bullets[i].vel_x != 0) ? SPR_PLAYER_SPLIT_BULLET : 4U);
        /* Bullet age feeds frame/tint, creating simple animated color aging. */
        hdmi_text_controller_set_sprite((uint8_t)(PLAYER_BULLET_BASE_SLOT + i), player_bullets[i].x, player_bullets[i].y,
                                        player_bullet_type,
                                        player_bullets[i].age >> 3,
                                        player_bullets[i].visible,
                                        (player_bullets[i].age >> 4) & 0x3U);
    }

    for (uint8_t i = 0U; i < MAX_ENEMY_BULLETS; i++) {
        int8_t vx = enemy_bullets[i].vel_x;
        uint8_t enemy_bullet_type = (vx <= -3 || vx >= 3 || enemy_bullets[i].vel_y <= 0) ?
                                    SPR_ENEMY_RING_BULLET :
                                    (((enemy_bullets[i].age >> 4) & 1U) ? SPR_ENEMY_SHARD_BULLET : 5U);
        hdmi_text_controller_set_sprite((uint8_t)(ENEMY_BULLET_BASE_SLOT + i), enemy_bullets[i].x, enemy_bullets[i].y,
                                        enemy_bullet_type, enemy_bullets[i].age >> 3,
                                        enemy_bullets[i].visible,
                                        0U);
    }

    for (uint8_t i = 0U; i < MAX_EXPLOSIONS; i++) {
        /* Explosion animation uses the Pic-derived compact atlas. */
        hdmi_text_controller_set_sprite((uint8_t)(EXPLOSION_BASE_SLOT + i),
                                        explosions[i].x, explosions[i].y,
                                        6U, explosions[i].frame,
                                        explosions[i].visible, 0U);
    }
    hdmi_text_controller_set_sprite(POWERUP_SLOT, powerup.x, powerup.y,
                                    powerup.sprite_type, powerup.frame,
                                    powerup.visible, powerup.tint);
    {
        uint8_t orbit_count = (power_level >= 2U) ? 8U : (power_level != 0U ? 4U : 0U);
        for (uint8_t i = 0U; i < 8U; i++) {
            if (game_state != PLAYING || i >= orbit_count) {
                hide_sprite_slot((uint8_t)(ORBIT_BULLET_BASE_SLOT + i));
                continue;
            }
            uint32_t phase = frame_ticks + i * (64U / orbit_count);
            int16_t ox = (int16_t)(player.x + 8 + wave16(phase) * 2);
            int16_t oy = (int16_t)(player.y + 8 + wave16(phase + 16U) * 2);
            hdmi_text_controller_set_sprite((uint8_t)(ORBIT_BULLET_BASE_SLOT + i), ox, oy,
                                            SPR_OPTION_ORB, (uint8_t)(frame_ticks >> 2),
                                            1U, (uint8_t)((i + weapon_mode) & 0x3U));
        }
    }
    hdmi_text_controller_set_sprite(BOSS_SPRITE_SLOT, boss.x, boss.y,
                                    boss.sprite_type, boss.frame,
                                    boss.visible, boss.tint);
    if (active_player_count() == 2U) {
        /* The second player occupies the former option slot, keeping the sprite budget fixed. */
    } else if (game_state == PLAYING && player.visible != 0U) {
        int16_t option_x = (int16_t)(player.x + 22 + wave16(frame_ticks >> 1) / 8);
        int16_t option_y = (int16_t)(player.y + 2 + wave16((frame_ticks >> 1) + 19U) / 10);
        if (focus_active != 0U) {
            hdmi_text_controller_set_sprite(DECORATION_SLOT, (int16_t)(player.x + 8), (int16_t)(player.y + 8),
                                            7U, (uint8_t)(frame_ticks >> 2), 1U, 0U);
        } else if (shield != 0U) {
            hdmi_text_controller_set_sprite(DECORATION_SLOT, option_x, option_y,
                                            SPR_OPTION_ORB, (uint8_t)(frame_ticks >> 2),
                                            1U, 0U);
        } else {
            hide_sprite_slot(DECORATION_SLOT);
        }
    } else {
        hide_sprite_slot(DECORATION_SLOT);
    }

    /* Right-side HUD text mirrors Imperishable Night while staying inside 16 characters per line. */
    text_label_u32(score_str, "SCORE ", score % 1000000000UL, 9U);
    text_label_u32(lives_str, "PLAYER ", lives, 2U);
    text_label_u32(spell_str, "SPELL ", shield, 1U);
    if (boss.visible != 0U) {
        text_label_u32(stage_str, "BOSS ", boss_hp, 3U);
    } else {
        text_label_u32(stage_str, "STAGE ", stage, 2U);
    }
    if (fire_level == FIRE_LEVEL_MAX || power_level == POWER_LEVEL_MAX) {
        text_copy(shield_str, "POWER MAX");
    } else {
        text_label_u32(shield_str, "POWER ", (uint8_t)(fire_level * 32U + power_level * 16U), 3U);
    }
    text_label_u32(graze_str, "GRAZE ", graze_score % 10000UL, 4U);
    {
        uint8_t pos;
        point_str[0] = '\0';
        pos = text_append(point_str, 0U, "POINT ");
        pos = text_append_u32(point_str, pos, point_items, 3U);
        (void)text_append(point_str, pos, "/500");
    }
    text_label_u32(time_str, "TIME ", stage_timer, 4U);
    if (barrier_ticks != 0U) {
        text_label_u32(time_str, "BORDER ", barrier_ticks, 3U);
    } else if (speed_ticks != 0U) {
        text_label_u32(time_str, "SPEED ", speed_ticks, 3U);
    } else if (score_boost_ticks != 0U) {
        text_copy(time_str, "SCORE X2");
    }
    stage_name = selected_endless != 0U ? "ENDLESS" : stage_config[stage_index()].name;
    boss_title = boss.visible != 0U ? stage_name : "STAGE START";
    hdmi_text_controller_set_text_at(0U, HUD_TEXT_X, 28U, "IN 6B BORDER", 0x9U);
    hdmi_text_controller_set_text_at(1U, HUD_TEXT_X, 62U, score_str, 0xFU);
    hdmi_text_controller_set_text_at(2U, HUD_TEXT_X, 96U, lives_str, 0xAU);
    hdmi_text_controller_set_text_at(3U, HUD_TEXT_X, 130U, spell_str, shield == 0U ? 0x4U : 0x9U);
    hdmi_text_controller_set_text_at(4U, HUD_TEXT_X, 164U, shield_str, 0xEU);
    hdmi_text_controller_set_text_at(5U, HUD_TEXT_X, 198U, graze_str, 0xCU);
    hdmi_text_controller_set_text_at(6U, HUD_TEXT_X, 232U, point_str, 0xFU);
    if (ready_ticks > (READY_START_TICKS * 2U / 3U)) {
        hdmi_text_controller_set_text_at(7U, HUD_TEXT_X, 266U, "READY 3", 0xEU);
    } else if (ready_ticks > (READY_START_TICKS / 3U)) {
        hdmi_text_controller_set_text_at(7U, HUD_TEXT_X, 266U, "READY 2", 0xEU);
    } else if (ready_ticks > 0U) {
        hdmi_text_controller_set_text_at(7U, HUD_TEXT_X, 266U, "READY 1", 0xEU);
    } else if (focus_active != 0U) {
        hdmi_text_controller_set_text_at(7U, HUD_TEXT_X, 266U, "FOCUS", 0x9U);
    } else {
        hdmi_text_controller_set_text_at(7U, HUD_TEXT_X, 266U, time_str, 0x6U);
    }
    hdmi_text_controller_set_text_at(8U, HUD_TEXT_X, 304U, "RANKING", 0xCU);
    for (uint8_t i = 0U; i < 5U; i++) {
        char rank_str[17];
        text_rank(rank_str, (uint8_t)(i + 1U), high_scores[i]);
        hdmi_text_controller_set_text_at((uint8_t)(9U + i), HUD_TEXT_X,
                                         (uint16_t)(330U + i * 26U), rank_str,
                                         i == 0U ? 0xEU : 0xCU);
    }
    hdmi_text_controller_set_text_at(14U, 38U, 24U, boss_title, boss.visible != 0U ? 0xFU : 0x9U);
    hdmi_text_controller_set_text_at(15U, 272U, 24U, stage_str, boss.visible != 0U ? 0x4U : 0x9U);
    if (game_state == WAITING_START) {
        hdmi_text_controller_set_text_at(7U, HUD_TEXT_X, 266U, "PRESS KEY", 0xEU);
    } else if (game_state == PAUSED) {
        hdmi_text_controller_set_text_at(7U, HUD_TEXT_X, 266U, "PAUSED R MENU", 0xEU);
    } else if (game_state == GAME_OVER) {
        hdmi_text_controller_set_text_at(7U, HUD_TEXT_X, 266U, "AUTO RETRY", 0xFU);
    } else if (game_state == WIN) {
        hdmi_text_controller_set_text_at(7U, HUD_TEXT_X, 266U, "YOU WIN", 0x2U);
    }
}

uint8_t get_key_pressed(uint8_t key) {
    return keys_pressed[key] != 0U;
}

void toggle_pause(void) {
    if (game_state == PLAYING) {
        game_state = PAUSED;
    } else if (game_state == PAUSED) {
        game_state = PLAYING;
    }
}

uint8_t check_game_over(void) {
    return game_state == GAME_OVER;
}

uint8_t check_win(void) {
    return game_state == WIN;
}

void display_game_over(void) {
    record_score_once();
    hdmi_text_controller_set_text_at(6U, HUD_TEXT_X, 232U, "GAME OVER", 0x4U);
    hdmi_text_controller_set_text_at(7U, HUD_TEXT_X, 266U, "AUTO RETRY", 0xFU);
}

void display_win(void) {
    record_score_once();
    hdmi_text_controller_set_text_at(6U, HUD_TEXT_X, 232U, "VICTORY!", 0x2U);
    hdmi_text_controller_set_text_at(7U, HUD_TEXT_X, 266U, "PRESS R", 0xFU);
}

uint32_t get_frame_counter(void) {
    return hdmi_text_controller_frame_counter();
}

#ifdef GAME_TEST_HOOKS
void game_test_spawn_powerup(uint8_t kind, int16_t x, int16_t y) {
    powerup_kind = (uint8_t)(kind % POWERUP_KIND_COUNT);
    powerup.x = x;
    powerup.y = y;
    powerup.visible = 1U;
    powerup.sprite_type = powerup_sprite_for_kind(powerup_kind);
    powerup.frame = 0U;
    powerup.tint = 0U;
}

uint8_t game_test_power_level(void) {
    return power_level;
}

uint8_t game_test_weapon_mode(void) {
    return weapon_mode;
}

uint8_t game_test_live_enemy_count(void) {
    return live_enemy_count();
}

uint8_t game_test_configured_enemy_count(void) {
    return configured_enemy_count();
}

uint8_t game_test_enemy_spacing_ok(void) {
    for (uint8_t a = 0U; a < NUM_ENEMIES; a++) {
        if (enemies[a].visible == 0U) {
            continue;
        }
        for (uint8_t b = (uint8_t)(a + 1U); b < NUM_ENEMIES; b++) {
            if (enemies[b].visible != 0U &&
                abs_i16((int16_t)(enemy_home_x[a] - enemy_home_x[b])) < ENEMY_SPAWN_MIN_DX &&
                abs_i16((int16_t)(enemy_home_y[a] - enemy_home_y[b])) < ENEMY_SPAWN_MIN_DY) {
                return 0U;
            }
            if (enemies[b].visible != 0U &&
                abs_i16((int16_t)(enemies[a].x - enemies[b].x)) < ENEMY_RENDER_MIN_DX &&
                abs_i16((int16_t)(enemies[a].y - enemies[b].y)) < ENEMY_RENDER_MIN_DY) {
                return 0U;
            }
        }
    }
    return 1U;
}

void game_test_set_player_position(int16_t x, int16_t y) {
    player.x = clamp_i16(x, PLAYER_MIN_X, PLAYER_MAX_X);
    player.y = clamp_i16(y, PLAYER_MIN_Y, PLAYER_MAX_Y);
}

int16_t game_test_first_enemy_x(void) {
    for (uint8_t i = 0U; i < NUM_ENEMIES; i++) {
        if (enemies[i].visible != 0U) {
            return enemies[i].x;
        }
    }
    return -1;
}

int16_t game_test_first_enemy_y(void) {
    for (uint8_t i = 0U; i < NUM_ENEMIES; i++) {
        if (enemies[i].visible != 0U) {
            return enemies[i].y;
        }
    }
    return -1;
}

int16_t game_test_first_enemy_home_y(void) {
    for (uint8_t i = 0U; i < NUM_ENEMIES; i++) {
        if (enemies[i].visible != 0U) {
            return enemy_home_y[i];
        }
    }
    return -1;
}

uint8_t game_test_first_enemy_entry_ticks(void) {
    for (uint8_t i = 0U; i < NUM_ENEMIES; i++) {
        if (enemies[i].visible != 0U) {
            return enemy_entry_ticks[i];
        }
    }
    return 0U;
}

uint8_t game_test_boss_visible(void) {
    return boss.visible;
}

int16_t game_test_boss_y(void) {
    return boss.y;
}

int16_t game_test_boss_home_y(void) {
    return boss_home_y;
}

uint8_t game_test_boss_entry_ticks(void) {
    return boss_entry_ticks;
}

void game_test_damage_player(uint8_t damage) {
    apply_player_damage_to(0U, damage);
}

void game_test_force_game_over(void) {
    lives = 0U;
    shield = 0U;
    game_state = GAME_OVER;
    game_over_ticks = 1U;
}

void game_test_force_boss_escort_case(void) {
    stage = 2U;
    ready_ticks = 0U;
    for (uint8_t i = 0U; i < NUM_ENEMIES; i++) {
        enemies[i].visible = 0U;
        enemy_hp[i] = 0U;
    }
    boss.visible = 1U;
    boss_kind = 1U;
    boss_home_x = 214;
    boss_home_y = 46;
    boss.x = boss_home_x;
    boss.y = PLAYFIELD_TOP;
    boss.sprite_type = SPR_BOSS_MID;
    boss.frame = 0U;
    boss.tint = 1U;
    boss_entry_ticks = 58U;
    boss_hp_max = 60U;
    boss_hp = 60U;
    frame_ticks = (uint32_t)(scaled_period(240U) - 1U);
}
#endif

#ifdef MB_NO_USB
static uint8_t demo_player_bullet_active(void) {
    for (uint8_t i = 0U; i < MAX_PLAYER_BULLETS; i++) {
        if (player_bullets[i].visible != 0U) {
            return 1U;
        }
    }
    return 0U;
}

static int16_t demo_clamp_player_x(int16_t x) {
    if (x < PLAYER_MIN_X) {
        return PLAYER_MIN_X;
    }
    if (x > PLAYER_MAX_X) {
        return PLAYER_MAX_X;
    }
    return x;
}

static int16_t demo_target_player_x(void) {
    uint8_t found = 0U;
    int16_t best_y = -32768;
    int16_t best_distance = 32767;
    int16_t target_x = player.x;
    uint16_t period = (uint16_t)(34U - stage * 4U);

    if (powerup.visible != 0U && powerup.y > 80) {
        return demo_clamp_player_x((int16_t)(powerup.x - 1));
    }

    if (period < 8U) {
        period = 8U;
    }

    for (uint8_t i = 0U; i < NUM_ENEMIES; i++) {
        if (enemies[i].visible != 0U) {
            /* Host/demo mode predicts where a shot should line up without USB input. */
            int16_t flight_frames = (int16_t)((PLAYER_START_Y - enemies[i].y) / 8);
            int16_t moves = (int16_t)((flight_frames + (int16_t)(period / 2U)) / (int16_t)period);
            int16_t predicted_x = (int16_t)(enemies[i].x + enemy_dir * 8 * moves);
            int16_t shot_x = demo_clamp_player_x((int16_t)(predicted_x - 1));
            int16_t distance = (int16_t)(shot_x > player.x ? shot_x - player.x : player.x - shot_x);

            if (found == 0U || enemies[i].y > best_y ||
                (enemies[i].y == best_y && distance < best_distance)) {
                found = 1U;
                best_y = enemies[i].y;
                best_distance = distance;
                target_x = shot_x;
            }
        }
    }

    return target_x;
}

static int16_t demo_target_player_y(void) {
    int16_t target_y = PLAYER_START_Y;

    if (powerup.visible != 0U && powerup.y > 120) {
        target_y = clamp_i16((int16_t)(powerup.y - 4), PLAYER_MIN_Y, PLAYER_MAX_Y);
    }

    /* Step away from nearby bullets so the autonomous demo can survive long enough for testing. */
    for (uint8_t i = 0U; i < MAX_ENEMY_BULLETS; i++) {
        if (enemy_bullets[i].visible != 0U &&
            enemy_bullets[i].y > (int16_t)(player.y - 70) &&
            enemy_bullets[i].y < (int16_t)(player.y + 34) &&
            enemy_bullets[i].x > (int16_t)(player.x - 22) &&
            enemy_bullets[i].x < (int16_t)(player.x + 38)) {
            target_y = (player.y > 360) ? (int16_t)(player.y - 36) : (int16_t)(player.y + 32);
            break;
        }
    }

    return clamp_i16(target_y, PLAYER_MIN_Y, PLAYER_MAX_Y);
}
#endif

void handle_usb_input(void) {
#ifdef MB_NO_USB
    for (uint16_t i = 0U; i < 256U; i++) {
        prev_keys[i] = keys_pressed[i];
        keys_pressed[i] = 0U;
    }

    if (game_state == GAME_OVER) {
        keys_pressed[KEY_R] = 1U;
        return;
    }

    if (game_state == WAITING_START) {
        keys_pressed[KEY_SPACE] = 1U;
        return;
    }

    if (game_state != PLAYING) {
        return;
    }

    {
        int16_t target_x = demo_target_player_x();
        int16_t target_y = demo_target_player_y();
        int16_t delta = (int16_t)(target_x - player.x);
        int16_t delta_y = (int16_t)(target_y - player.y);
        uint8_t bullet_active = demo_player_bullet_active();

        if (delta > 2) {
            keys_pressed[KEY_RIGHT] = 1U;
        } else if (delta < -2) {
            keys_pressed[KEY_LEFT] = 1U;
        }

        if (delta_y > 3) {
            keys_pressed[KEY_DOWN] = 1U;
        } else if (delta_y < -3) {
            keys_pressed[KEY_UP] = 1U;
        }

        if (bullet_active == 0U && delta >= -3 && delta <= 3) {
            keys_pressed[KEY_SPACE] = 1U;
        }
    }
#else
    HIDKeyboardReport report;

    for (uint16_t i = 0U; i < 256U; i++) {
        prev_keys[i] = keys_pressed[i];
        keys_pressed[i] = 0U;
    }

    if (usb_poll() == 0U) {
        return;
    }

    usb_read_report(&report);
    for (uint8_t i = 0U; i < HID_KEYBOARD_MAX_KEYS; i++) {
        if (report.keycodes[i] != 0U) {
            keys_pressed[report.keycodes[i]] = 1U;
        }
    }
#endif
}
