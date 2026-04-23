.extern uart_rx
.extern uart_tx
.global _start
.section .text.start
_start:
    la sp, stack_bottom
    call uart_rx
    call uart_tx
    j _start

.section bss
    .space 0x100
stack_bottom: