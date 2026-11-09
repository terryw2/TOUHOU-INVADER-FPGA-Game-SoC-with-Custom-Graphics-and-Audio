#ifndef GAME_ASSETS_H
#define GAME_ASSETS_H

#include <stdint.h>

typedef struct {
    uint16_t hz;
    uint8_t volume;
    uint8_t duration_ms;
    uint8_t pan;
} GameNote;

extern const GameNote g_music_lead[];
extern const uint8_t g_music_lead_count;
extern const GameNote g_music_luna_dial[];
extern const uint8_t g_music_luna_dial_count;
extern const GameNote g_music_bass[];
extern const uint8_t g_music_bass_count;

extern const uint16_t g_enemy_wave_seed[];
extern const uint8_t g_enemy_wave_seed_count;

#endif
