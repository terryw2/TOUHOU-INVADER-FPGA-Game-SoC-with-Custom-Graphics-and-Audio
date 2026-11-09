#include "ddr_runtime.h"

#if defined(MB_HAS_AXI_DDR)
#include "xparameters.h"

#ifdef MB_DDR4_STATUS_READY
# ifndef DDR4_STATUS_BASE_ADDR
#  ifdef XPAR_DDR4_STATUS_AXI_0_BASEADDR
#   define DDR4_STATUS_BASE_ADDR XPAR_DDR4_STATUS_AXI_0_BASEADDR
#  elif defined(XPAR_DDR4_STATUS_AXI_0_S_AXI_BASEADDR)
#   define DDR4_STATUS_BASE_ADDR XPAR_DDR4_STATUS_AXI_0_S_AXI_BASEADDR
#  else
#   define DDR4_STATUS_BASE_ADDR 0x44A20000U
#  endif
# endif
# define DDR_READY_REG (*(volatile uint32_t *)(DDR4_STATUS_BASE_ADDR + 0x00U))
#else
# ifndef DDR_READY_GPIO_BASE_ADDR
#  ifdef XPAR_GPIO_DDR_READY_BASEADDR
#   define DDR_READY_GPIO_BASE_ADDR XPAR_GPIO_DDR_READY_BASEADDR
#  elif defined(XPAR_GPIO_DDR_READY_S_AXI_BASEADDR)
#   define DDR_READY_GPIO_BASE_ADDR XPAR_GPIO_DDR_READY_S_AXI_BASEADDR
#  else
#   define DDR_READY_GPIO_BASE_ADDR 0x40670000U
#  endif
# endif
# define DDR_READY_REG (*(volatile uint32_t *)(DDR_READY_GPIO_BASE_ADDR + 0x00U))
#endif

extern uint8_t __ddr_bss_start[];
extern uint8_t __ddr_bss_end[];

uint8_t ddr_runtime_wait_ready(uint32_t timeout) {
    while (timeout-- != 0U) {
        if ((DDR_READY_REG & 0x1U) != 0U) {
            return 1U;
        }
    }
    return 0U;
}

void ddr_runtime_clear_bss(void) {
    uint8_t *p = __ddr_bss_start;

    while (p < __ddr_bss_end) {
        *p++ = 0U;
    }
}

uint32_t ddr_runtime_bss_bytes(void) {
    return (uint32_t)(__ddr_bss_end - __ddr_bss_start);
}

#else

uint8_t ddr_runtime_wait_ready(uint32_t timeout) {
    (void)timeout;
    return 1U;
}

void ddr_runtime_clear_bss(void) {
}

uint32_t ddr_runtime_bss_bytes(void) {
    return 0U;
}

#endif
