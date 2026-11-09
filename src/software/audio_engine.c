#include "audio_engine.h"

#ifdef MB_NO_AUDIO

void audio_engine_init(void) {
}

void audio_engine_silence(void) {
}

void audio_engine_tick(void) {
}

void audio_engine_play_boot(void) {
}

void audio_engine_play_shoot(void) {
}

void audio_engine_play_explosion(void) {
}

void audio_engine_play_player_hit(void) {
}

void audio_engine_play_stage_clear(void) {
}

#else

#include "game_assets.h"

#define AUDIO_CONTROL        0x00U
#define AUDIO_CH_PERIOD(ch)  (0x04U + ((uint32_t)(ch) * 0x10U))
#define AUDIO_CH_VOLUME(ch)  (0x08U + ((uint32_t)(ch) * 0x10U))
#define AUDIO_CH_DURATION(ch) (0x0CU + ((uint32_t)(ch) * 0x10U))
#define AUDIO_CH_PAN(ch)     (0x10U + ((uint32_t)(ch) * 0x10U))

#define AUDIO_ENABLE         0x00000001U
#define AUDIO_CLK_HZ         100000000UL
#define AUDIO_FRAME_HZ       60U
#define ARRAY_COUNT(a)       ((uint8_t)(sizeof(a) / sizeof((a)[0])))

typedef struct {
    uint16_t hz;
    uint8_t volume;
    uint8_t duration_ms;
    uint8_t pan;
} SfxStep;

typedef struct {
    const SfxStep *steps;
    uint8_t count;
    uint8_t priority;
} SfxPattern;

static const SfxStep sfx_boot[] = {
    {523U, 62U, 55U, 1U},
    {784U, 62U, 55U, 2U},
    {1046U, 54U, 80U, 0U},
};

static const SfxStep sfx_shoot[] = {
    {1760U, 72U, 24U, 1U},
    {1320U, 50U, 18U, 2U},
    {988U, 34U, 18U, 0U},
};

static const SfxStep sfx_explosion[] = {
    {96U, 92U, 42U, 0U},
    {144U, 72U, 28U, 1U},
    {72U, 88U, 58U, 2U},
    {52U, 62U, 80U, 0U},
};

static const SfxStep sfx_player_hit[] = {
    {196U, 96U, 70U, 0U},
    {147U, 84U, 82U, 0U},
    {98U, 72U, 110U, 0U},
};

static const SfxStep sfx_stage_clear[] = {
    {523U, 68U, 70U, 1U},
    {659U, 70U, 70U, 2U},
    {784U, 72U, 90U, 1U},
    {1046U, 62U, 130U, 2U},
};

static uint32_t audio_frame_counter;
static uint32_t audio_lead_next_frame;
static uint32_t audio_bass_next_frame;
static uint32_t sfx_next_frame;
static uint8_t audio_lead_index;
static uint8_t audio_bass_index;
static SfxPattern sfx_current;
static uint8_t sfx_index;

static void tick_sfx(void);

static uint32_t period_from_hz(uint32_t hz) {
    if (hz == 0U) {
        return 0U;
    }

    return (AUDIO_CLK_HZ / (hz * 2UL));
}

static void play_channel(uint8_t channel, uint32_t hz, uint8_t volume,
                         uint16_t duration_ms, uint8_t pan) {
    AUDIO_REG(AUDIO_CH_PERIOD(channel)) = period_from_hz(hz);
    AUDIO_REG(AUDIO_CH_PAN(channel)) = pan;
    AUDIO_REG(AUDIO_CH_DURATION(channel)) = duration_ms;
    AUDIO_REG(AUDIO_CH_VOLUME(channel)) = volume;
}

static uint32_t frames_from_ms(uint16_t duration_ms) {
    uint32_t frames = ((uint32_t)duration_ms * AUDIO_FRAME_HZ + 999U) / 1000U;
    return frames == 0U ? 1U : frames;
}

static void start_sfx(const SfxStep *steps, uint8_t count, uint8_t priority) {
    if (count == 0U || steps == 0) {
        return;
    }
    if (sfx_current.count != 0U && priority < sfx_current.priority) {
        return;
    }
    sfx_current.steps = steps;
    sfx_current.count = count;
    sfx_current.priority = priority;
    sfx_index = 0U;
    sfx_next_frame = audio_frame_counter;
    tick_sfx();
}

static void tick_sfx(void) {
    const SfxStep *step;

    if (sfx_current.count == 0U || audio_frame_counter < sfx_next_frame) {
        return;
    }

    step = &sfx_current.steps[sfx_index];
    play_channel(1U, step->hz, step->volume, step->duration_ms, step->pan);
    sfx_next_frame = audio_frame_counter + frames_from_ms(step->duration_ms);
    sfx_index++;
    if (sfx_index >= sfx_current.count) {
        sfx_current.steps = 0;
        sfx_current.count = 0U;
        sfx_current.priority = 0U;
        sfx_index = 0U;
    }
}

void audio_engine_init(void) {
    AUDIO_REG(AUDIO_CONTROL) = AUDIO_ENABLE;
    audio_engine_silence();
    audio_frame_counter = 0U;
    audio_lead_next_frame = 0U;
    audio_bass_next_frame = 0U;
    sfx_next_frame = 0U;
    audio_lead_index = 0U;
    audio_bass_index = 0U;
    sfx_current.steps = 0;
    sfx_current.count = 0U;
    sfx_current.priority = 0U;
    sfx_index = 0U;
}

void audio_engine_silence(void) {
    for (uint8_t ch = 0U; ch < 3U; ch++) {
        AUDIO_REG(AUDIO_CH_VOLUME(ch)) = 0U;
        AUDIO_REG(AUDIO_CH_DURATION(ch)) = 0U;
        AUDIO_REG(AUDIO_CH_PERIOD(ch)) = 0U;
        AUDIO_REG(AUDIO_CH_PAN(ch)) = 0U;
    }
}

void audio_engine_tick(void) {
    const GameNote *note;
    audio_frame_counter++;

    /* Background music is a tiny sequencer; one MIDI-derived lead and one bass channel loop. */
    if (g_music_luna_dial_count != 0U && audio_frame_counter >= audio_lead_next_frame) {
        note = &g_music_luna_dial[audio_lead_index];
        play_channel(0U, note->hz, note->volume, note->duration_ms, note->pan);
        audio_lead_next_frame = audio_frame_counter + frames_from_ms(note->duration_ms);
        audio_lead_index++;
        if (audio_lead_index >= g_music_luna_dial_count) {
            audio_lead_index = 0U;
        }
    }

    if (g_music_bass_count != 0U && audio_frame_counter >= audio_bass_next_frame) {
        note = &g_music_bass[audio_bass_index];
        play_channel(2U, note->hz, note->volume, note->duration_ms, note->pan);
        audio_bass_next_frame = audio_frame_counter + frames_from_ms(note->duration_ms);
        audio_bass_index++;
        if (audio_bass_index >= g_music_bass_count) {
            audio_bass_index = 0U;
        }
    }

    tick_sfx();
}

void audio_engine_play_boot(void) {
    (void)sfx_boot;
}

void audio_engine_play_shoot(void) {
    (void)sfx_shoot;
}

void audio_engine_play_explosion(void) {
    start_sfx(sfx_explosion, ARRAY_COUNT(sfx_explosion), 3U);
}

void audio_engine_play_player_hit(void) {
    start_sfx(sfx_player_hit, ARRAY_COUNT(sfx_player_hit), 4U);
}

void audio_engine_play_stage_clear(void) {
    (void)sfx_stage_clear;
}

#endif
