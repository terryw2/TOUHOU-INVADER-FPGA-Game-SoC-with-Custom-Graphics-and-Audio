#ifndef AUDIO_ENGINE_H
#define AUDIO_ENGINE_H

#include <stdint.h>

#ifndef AUDIO_BASE_ADDR
# ifdef XPAR_AUDIO_ENGINE_0_BASEADDR
#  define AUDIO_BASE_ADDR XPAR_AUDIO_ENGINE_0_BASEADDR
# elif defined(XPAR_AUDIO_ENGINE_0_S_AXI_BASEADDR)
#  define AUDIO_BASE_ADDR XPAR_AUDIO_ENGINE_0_S_AXI_BASEADDR
# else
#  define AUDIO_BASE_ADDR 0x44A10000U
# endif
#endif

#define AUDIO_REG(offset) (*(volatile uint32_t *)(AUDIO_BASE_ADDR + (offset)))

void audio_engine_init(void);
void audio_engine_silence(void);
void audio_engine_tick(void);
void audio_engine_play_boot(void);
void audio_engine_play_shoot(void);
void audio_engine_play_explosion(void);
void audio_engine_play_player_hit(void);
void audio_engine_play_stage_clear(void);

#endif
