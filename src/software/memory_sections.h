#ifndef MEMORY_SECTIONS_H
#define MEMORY_SECTIONS_H

#if defined(MB_HAS_AXI_DDR)
#define DDR_BSS_SECTION __attribute__((section(".ddr_bss")))
#else
#define DDR_BSS_SECTION
#endif

#endif
