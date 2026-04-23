.extern main
.global _start
.section .text.start
_start:
    la sp, stack_bottom
    call main
loop:
    j loop

.section .stack
    .space 0x100
stack_bottom: