#ifndef HDMI_MMIO_MOCK_H
#define HDMI_MMIO_MOCK_H

#include <stdint.h>

#define HDMI_TEST_REG_WORDS 8192U

extern volatile uint32_t hdmi_test_regs[HDMI_TEST_REG_WORDS];
extern volatile uint32_t audio_test_regs[16];

#endif
