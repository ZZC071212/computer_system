.section .text.entry
    .align 4
    .globl _traps
    .globl __dummy
    .globl __switch_to
    
__dummy:
    la   t0,dummy_task
    csrw sepc, t0
    sret

_traps:
    # 1. 将寄存器和 sepc 保存到栈上
    sd   sp,  -8(sp)
    sd   ra,  -16(sp)
    sd   gp,  -24(sp)
    sd   tp,  -32(sp)
    sd   t0,  -40(sp)
    sd   t1,  -48(sp)
    sd   t2,  -56(sp)
    sd   s0,  -64(sp)
    sd   s1,  -72(sp)
    sd   a0,  -80(sp)
    sd   a1,  -88(sp)
    sd   a2,  -96(sp)
    sd   a3,  -104(sp)
    sd   a4,  -112(sp)
    sd   a5,  -120(sp)
    sd   a6,  -128(sp)
    sd   a7,  -136(sp)
    sd   s2,  -144(sp)
    sd   s3,  -152(sp)
    sd   s4,  -160(sp)
    sd   s5,  -168(sp)
    sd   s6,  -176(sp)
    sd   s7,  -184(sp)
    sd   s8,  -192(sp)
    sd   s9,  -200(sp)
    sd   s10, -208(sp)
    sd   s11, -216(sp)
    sd   t3,  -224(sp)
    sd   t4,  -232(sp)
    sd   t5,  -240(sp)
    sd   t6,  -248(sp)
    addi sp, sp, -248

    # 2. 调用 trap_handler
    csrr a0, scause
    csrr a1, sepc
    call trap_handler

    # 3. 恢复寄存器和 sepc
    #    特别注意 sp 寄存器的恢复
    ld t6, 0(sp)        
    ld t5, 8(sp)
    ld t4, 16(sp)
    ld t3, 24(sp)
    ld s11, 32(sp)
    ld s10, 40(sp)
    ld s9, 48(sp)
    ld s8, 56(sp)
    ld s7, 64(sp)
    ld s6, 72(sp)
    ld s5, 80(sp)
    ld s4, 88(sp)
    ld s3, 96(sp)
    ld s2, 104(sp)
    ld a7, 112(sp)
    ld a6, 120(sp)
    ld a5, 128(sp)
    ld a4, 136(sp)
    ld a3, 144(sp)
    ld a2, 152(sp)
    ld a1, 160(sp)
    ld a0, 168(sp)
    ld s1, 176(sp)
    ld s0, 184(sp)
    ld t2, 192(sp)
    ld t1, 200(sp)
    ld t0, 208(sp)
    ld tp, 216(sp)
    ld gp, 224(sp)
    ld ra, 232(sp)
    ld sp, 240(sp)

    # 4. 返回
    sret


__switch_to:
    # a0 = prev, a1 = next

    # 保存 ra, sp（根据结构体偏移）
    sd      ra, 32(a0)          # prev->thread.ra（偏移32）
    sd      sp, 40(a0)          # prev->thread.sp（偏移40）

    # 保存 s0~s11
    sd      s0,  48(a0)         # prev->thread.s[0]（偏移48）
    sd      s1,  56(a0)         # prev->thread.s[1]（偏移56）
    sd      s2,  64(a0)         # prev->thread.s[2]（偏移64）
    sd      s3,  72(a0)         # prev->thread.s[3]（偏移72）
    sd      s4,  80(a0)         # prev->thread.s[4]（偏移80）
    sd      s5,  88(a0)         # prev->thread.s[5]（偏移88）
    sd      s6,  96(a0)         # prev->thread.s[6]（偏移96）
    sd      s7,  104(a0)        # prev->thread.s[7]（偏移104）
    sd      s8,  112(a0)        # prev->thread.s[8]（偏移112）
    sd      s9,  120(a0)        # prev->thread.s[9]（偏移120）
    sd      s10, 128(a0)        # prev->thread.s[10]（偏移128）
    sd      s11, 136(a0)        # prev->thread.s[11]（偏移136）

    # 恢复 ra, sp
    ld      ra, 32(a1)          # next->thread.ra（偏移32）
    ld      sp, 40(a1)          # next->thread.sp（偏移40）

    # 恢复 s0~s11
    ld      s0,  48(a1)         # next->thread.s[0]
    ld      s1,  56(a1)         # next->thread.s[1]
    ld      s2,  64(a1)         # next->thread.s[2]
    ld      s3,  72(a1)         # next->thread.s[3]
    ld      s4,  80(a1)         # next->thread.s[4]
    ld      s5,  88(a1)         # next->thread.s[5]
    ld      s6,  96(a1)         # next->thread.s[6]
    ld      s7,  104(a1)        # next->thread.s[7]
    ld      s8,  112(a1)        # next->thread.s[8]
    ld      s9,  120(a1)        # next->thread.s[9]
    ld      s10, 128(a1)        # next->thread.s[10]
    ld      s11, 136(a1)        # next->thread.s[11]

    ret