#include "memory_test.h"

#ifndef MB_SKIP_DDR_TEST

#ifndef MB_NO_STDOUT
#include "xil_printf.h"
#define MB_PRINTF(...) xil_printf(__VA_ARGS__)
#else
#define MB_PRINTF(...) do { } while (0)
#endif

#include "xparameters.h"

#ifdef MB_DDR4_STATUS_BIST

#ifndef DDR4_STATUS_BASE_ADDR
# ifdef XPAR_DDR4_STATUS_AXI_0_BASEADDR
#  define DDR4_STATUS_BASE_ADDR XPAR_DDR4_STATUS_AXI_0_BASEADDR
# elif defined(XPAR_DDR4_STATUS_AXI_0_S_AXI_BASEADDR)
#  define DDR4_STATUS_BASE_ADDR XPAR_DDR4_STATUS_AXI_0_S_AXI_BASEADDR
# else
#  define DDR4_STATUS_BASE_ADDR 0x44A20000U
# endif
#endif

#ifndef DDR4_STATUS_TIMEOUT
#define DDR4_STATUS_TIMEOUT 60000000UL
#endif

#define DDR4_STATUS_REG       (*(volatile uint32_t *)(DDR4_STATUS_BASE_ADDR + 0x00U))
#define DDR4_PROGRESS_REG     (*(volatile uint32_t *)(DDR4_STATUS_BASE_ADDR + 0x04U))
#define DDR4_ERROR_INDEX_REG  (*(volatile uint32_t *)(DDR4_STATUS_BASE_ADDR + 0x08U))

uint8_t ddr3_memory_test(void) {
    MB_PRINTF("DDR4 BIST status base 0x%08lx\r\n", (unsigned long)DDR4_STATUS_BASE_ADDR);

    for (uint32_t timeout = 0U; timeout < DDR4_STATUS_TIMEOUT; timeout++) {
        uint32_t status = DDR4_STATUS_REG;

        if ((status & 0x8U) != 0U) {
            MB_PRINTF("DDR4 FAIL progress 0x%08lx error index %lu\r\n",
                      (unsigned long)DDR4_PROGRESS_REG,
                      (unsigned long)DDR4_ERROR_INDEX_REG);
            return 0U;
        }

        if ((status & 0x6U) == 0x6U) {
            MB_PRINTF("DDR4 PASS progress 0x%08lx\r\n",
                      (unsigned long)DDR4_PROGRESS_REG);
            return 1U;
        }
    }

    MB_PRINTF("DDR4 TIMEOUT status 0x%08lx progress 0x%08lx\r\n",
              (unsigned long)DDR4_STATUS_REG,
              (unsigned long)DDR4_PROGRESS_REG);
    return 0U;
}

#else

#ifndef DDR3_BASE_ADDR
# ifdef XPAR_MIG_7SERIES_0_BASEADDR
#  define DDR3_BASE_ADDR XPAR_MIG_7SERIES_0_BASEADDR
# elif defined(XPAR_MIG_7SERIES_0_S_AXI_BASEADDR)
#  define DDR3_BASE_ADDR XPAR_MIG_7SERIES_0_S_AXI_BASEADDR
# elif defined(XPAR_MIG_7SERIES_0_C0_DDR3_S_AXI_BASEADDR)
#  define DDR3_BASE_ADDR XPAR_MIG_7SERIES_0_C0_DDR3_S_AXI_BASEADDR
# elif defined(XPAR_MEMORY_BASEADDR)
#  define DDR3_BASE_ADDR XPAR_MEMORY_BASEADDR
# else
#  define DDR3_BASE_ADDR 0x80000000U
# endif
#endif

#ifndef DDR3_TEST_WORDS
#define DDR3_TEST_WORDS 1024U
#endif

uint8_t ddr3_memory_test(void) {
    volatile uint32_t *mem = (volatile uint32_t *)(DDR3_BASE_ADDR + 0x00100000U);
    uint32_t patterns[] = {
        0x00000000UL,
        0xFFFFFFFFUL,
        0xA5A55A5AUL,
        0x13572468UL
    };

    MB_PRINTF("DDR3 test base 0x%08lx\r\n", (unsigned long)DDR3_BASE_ADDR);

    for (uint32_t p = 0U; p < (sizeof(patterns) / sizeof(patterns[0])); p++) {
        for (uint32_t i = 0U; i < DDR3_TEST_WORDS; i++) {
            mem[i] = patterns[p] ^ (i * 0x01010101UL);
        }

        for (uint32_t i = 0U; i < DDR3_TEST_WORDS; i++) {
            uint32_t expected = patterns[p] ^ (i * 0x01010101UL);
            uint32_t actual = mem[i];
            if (actual != expected) {
                MB_PRINTF("DDR3 FAIL p%lu i%lu exp 0x%08lx got 0x%08lx\r\n",
                          (unsigned long)p, (unsigned long)i,
                          (unsigned long)expected, (unsigned long)actual);
                return 0U;
            }
        }
    }

    MB_PRINTF("DDR3 PASS\r\n");
    return 1U;
}

#endif

#else

uint8_t ddr3_memory_test(void) {
    return 1U;
}

#endif
