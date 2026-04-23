OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS {
    . = 0x80200000;
    .text : ALIGN(0x1000) {
        *(.text.init)
        *(.text .text.*)
    }

    .bss : ALIGN(0x1000) {
        *(.bss.stack)
        _sbss = .;
        *(.bss .bss.*)
        _ebss = .;
    }
}
