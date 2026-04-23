OUTPUT_ARCH("riscv")

ENTRY(_start)

SECTIONS
{
    . = 0;

    .text : {
        *(.text.init)
        *(.text .text.*)
    }

    .data : {
        *(.data .data.*)
    }

    .rodata : {
        *(.rodata .rodata*)
    }

    .bss : {
        *(.sbss .sbss.*)
        *(.bss .bss.*)
    }
}
