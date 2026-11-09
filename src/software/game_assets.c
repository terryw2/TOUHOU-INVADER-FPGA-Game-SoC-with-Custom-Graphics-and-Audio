#include "game_assets.h"
#include "luna_dial_bgm.h"

const GameNote g_music_lead[] = {
    {659U, 28U, 70U, 1U},
    {784U, 24U, 70U, 2U},
    {880U, 26U, 70U, 1U},
    {988U, 22U, 70U, 2U},
    {880U, 26U, 70U, 1U},
    {784U, 24U, 70U, 2U},
    {740U, 22U, 70U, 1U},
    {880U, 24U, 95U, 2U},
    {1046U, 20U, 70U, 1U},
    {988U, 22U, 70U, 2U},
    {880U, 24U, 70U, 1U},
    {784U, 26U, 110U, 2U},
};
const uint8_t g_music_lead_count = (uint8_t)(sizeof(g_music_lead) / sizeof(g_music_lead[0]));

const GameNote g_music_bass[] = {
    {196U, 20U, 85U, 0U},
    {247U, 18U, 85U, 0U},
    {220U, 19U, 85U, 0U},
    {294U, 18U, 85U, 0U},
};
const uint8_t g_music_bass_count = (uint8_t)(sizeof(g_music_bass) / sizeof(g_music_bass[0]));

const uint16_t g_enemy_wave_seed[] = {
    3U, 11U, 19U, 29U, 41U, 52U, 61U,
    7U, 17U, 23U, 37U, 47U, 56U, 63U,
    5U, 13U, 31U, 43U, 53U, 57U, 62U,
    2U, 29U, 34U, 46U, 58U, 60U, 64U,
};
const uint8_t g_enemy_wave_seed_count = (uint8_t)(sizeof(g_enemy_wave_seed) / sizeof(g_enemy_wave_seed[0]));
