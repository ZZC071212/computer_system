/* 目标架构 */
OUTPUT_ARCH( "riscv" )

/* 程序入口 */
ENTRY( _start )

/* kernel代码起始位置 */
BASE_ADDR = 0x80000000;

SECTIONS
{
    .rom.text 0x00000000 : {../rom/rom.o(.text)}
    . = ALIGN(0x10);
    .rom.data : {../rom/rom.o(.data)}

    . = BASE_ADDR;

    _skernel = .;
    
    .text : ALIGN(0x1000){
        _stext = .;
        *(.text.init)
        *(.text .text.*)
        _etext = .;
    }

    .rodata : ALIGN(0x1000){
        _srodata = .;
        *(.rodata .rodata.*)
        _erodata = .;
    }

    .data : ALIGN(0x1000){
        _sdata = .;
        *(.data .data.*)
        _edata = .;
    }

    .bss : ALIGN(0x1000){
        _sbss = .;
        *(.bss.stack)
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        _ebss = .;
    }

    _ekernel = .;
}
