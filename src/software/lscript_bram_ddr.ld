_STACK_SIZE = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0x1000;
_HEAP_SIZE = DEFINED(_HEAP_SIZE) ? _HEAP_SIZE : 0x400;

MEMORY
{
   bram_vectors : ORIGIN = 0x0, LENGTH = 0x50
   local_bram : ORIGIN = 0x50, LENGTH = 0x1FFB0
   mig_7series_0_memaddr : ORIGIN = 0x80000000, LENGTH = 0x08000000
}

ENTRY(_start)

SECTIONS
{
.vectors.reset 0x0 : { KEEP (*(.vectors.reset)) } > bram_vectors
.vectors.sw_exception 0x8 : { KEEP (*(.vectors.sw_exception)) } > bram_vectors
.vectors.interrupt 0x10 : { KEEP (*(.vectors.interrupt)) } > bram_vectors
.vectors.hw_exception 0x20 : { KEEP (*(.vectors.hw_exception)) } > bram_vectors

.text : {
   *(.text)
   *(.text.*)
   *(.gnu.linkonce.t.*)
   KEEP (*(.init))
   KEEP (*(.fini))
} > local_bram

.ctors : {
   __CTOR_LIST__ = .;
   ___CTORS_LIST___ = .;
   KEEP (*crtbegin.o(.ctors))
   KEEP (*(EXCLUDE_FILE(*crtend.o) .ctors))
   KEEP (*(SORT(.ctors.*)))
   KEEP (*(.ctors))
   __CTOR_END__ = .;
   ___CTORS_END___ = .;
} > local_bram

.dtors : {
   __DTOR_LIST__ = .;
   ___DTORS_LIST___ = .;
   KEEP (*crtbegin.o(.dtors))
   KEEP (*(EXCLUDE_FILE(*crtend.o) .dtors))
   KEEP (*(SORT(.dtors.*)))
   KEEP (*(.dtors))
   PROVIDE(__DTOR_END__ = .);
   PROVIDE(___DTORS_END___ = .);
} > local_bram

.rodata : {
   __rodata_start = .;
   *(.rodata)
   *(.rodata.*)
   *(.gnu.linkonce.r.*)
   __rodata_end = .;
} > local_bram

.sdata2 : {
   . = ALIGN(8);
   __sdata2_start = .;
   *(.sdata2)
   *(.sdata2.*)
   *(.gnu.linkonce.s2.*)
   . = ALIGN(8);
   __sdata2_end = .;
} > local_bram

.sbss2 : {
   __sbss2_start = .;
   *(.sbss2)
   *(.sbss2.*)
   *(.gnu.linkonce.sb2.*)
   __sbss2_end = .;
} > local_bram

.data : {
   . = ALIGN(4);
   __data_start = .;
   *(.data)
   *(.data.*)
   *(.gnu.linkonce.d.*)
   __data_end = .;
} > local_bram

.got : { *(.got) } > local_bram
.got1 : { *(.got1) } > local_bram
.got2 : { *(.got2) } > local_bram
.eh_frame : { *(.eh_frame) } > local_bram
.jcr : { *(.jcr) } > local_bram
.gcc_except_table : { *(.gcc_except_table) } > local_bram

.sdata : {
   . = ALIGN(8);
   __sdata_start = .;
   *(.sdata)
   *(.sdata.*)
   *(.gnu.linkonce.s.*)
   __sdata_end = .;
} > local_bram

.sbss (NOLOAD) : {
   . = ALIGN(4);
   __sbss_start = .;
   *(.sbss)
   *(.sbss.*)
   *(.gnu.linkonce.sb.*)
   . = ALIGN(8);
   __sbss_end = .;
} > local_bram

.tdata : {
   __tdata_start = .;
   *(.tdata)
   *(.tdata.*)
   *(.gnu.linkonce.td.*)
   __tdata_end = .;
} > local_bram

.tbss : {
   __tbss_start = .;
   *(.tbss)
   *(.tbss.*)
   *(.gnu.linkonce.tb.*)
   __tbss_end = .;
} > local_bram

.bss (NOLOAD) : {
   . = ALIGN(4);
   __bss_start = .;
   *(.bss)
   *(.bss.*)
   *(.gnu.linkonce.b.*)
   *(COMMON)
   . = ALIGN(4);
   __bss_end = .;
} > local_bram

_SDA_BASE_ = __sdata_start + ((__sbss_end - __sdata_start) / 2);
_SDA2_BASE_ = __sdata2_start + ((__sbss2_end - __sdata2_start) / 2);

.heap (NOLOAD) : {
   . = ALIGN(8);
   _heap = .;
   _heap_start = .;
   . += _HEAP_SIZE;
   _heap_end = .;
} > local_bram

.stack (NOLOAD) : {
   _stack_end = .;
   . += _STACK_SIZE;
   . = ALIGN(8);
   _stack = .;
   __stack = _stack;
} > local_bram
_bram_end = .;

.ddr_bss (NOLOAD) : {
   . = ALIGN(8);
   __ddr_bss_start = .;
   *(.ddr_bss)
   *(.ddr_bss.*)
   . = ALIGN(8);
   __ddr_bss_end = .;
} > mig_7series_0_memaddr

_end = _bram_end;
ASSERT(_stack <= ORIGIN(local_bram) + LENGTH(local_bram), "BRAM overflow")
}
