    .section .text
    .globl _start1
_start1:
    li sp, 0x1000
    li a0, 0x10000
    call load_binary
    li t0, 0x80000000
    jr t0

    .section .data
    .incbin	FW_PAYLOAD_PATH
