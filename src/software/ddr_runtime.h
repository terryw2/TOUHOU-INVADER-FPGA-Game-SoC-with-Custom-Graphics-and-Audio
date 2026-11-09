#ifndef DDR_RUNTIME_H
#define DDR_RUNTIME_H

#include <stdint.h>

uint8_t ddr_runtime_wait_ready(uint32_t timeout);
void ddr_runtime_clear_bss(void);
uint32_t ddr_runtime_bss_bytes(void);

#endif
