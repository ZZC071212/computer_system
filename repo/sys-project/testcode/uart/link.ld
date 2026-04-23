OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x0;
  .text : { 
    *(.text.start)
    *(.text) 
  }
  . = ALIGN(0x10);
  .data : { *(.data) }
  . = ALIGN(0x10);
  .rodata : { *(.rodata) }
  . = ALIGN(0x10);
  .bss : { *(.bss) }
  _end = .;
}

