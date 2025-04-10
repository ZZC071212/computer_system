<style>
code {
    font-family: ui-monospace, Cascadia, SFMono-Regular, Consolas, Menlo, monospace;
}
</style>

# 实验 4：RV64 用户模式

!!! info "25.04.16 发布、25.04.30 截止提交（两周）"

## 实验目的

- 创建用户态进程，并设置 `sstatus` 来完成内核态转换至用户态。
- 正确设置用户进程的**用户态栈**和**内核态栈**，并在异常处理时正确切换。
- 补充异常处理逻辑，完成指定的 syscall（`sys_write`、`sys_getpid`）功能。

## 实验环境

- Debian 12 / Ubuntu 24.04 / ~~Ubuntu 22.04~~

## 背景知识

在 [Lab3](lab3.md) 中，我们开启了虚拟内存，这为进程间地址空间相互隔离打下了基础。之前的实验中我们只创建了内核进程，它们共用地址空间（共用一个**内核页表** `swapper_pg_dir`）。在本次实验中我们将引入用户态进程：

- 当启动用户模式应用程序时，内核将为该应用程序创建一个进程，为应用程序提供了专用虚拟地址空间等资源。
- 因为应用程序的虚拟地址空间是私有的，所以一个应用程序无法更改属于另一个应用程序的数据。
- 每个应用程序都是独立运行的，如果一个应用程序崩溃，其他应用程序和 OS 不会受到影响。
- 同时，用户模式应用程序可访问的虚拟地址空间也受到限制，在用户模式下无法访问内核的虚拟地址，防止应用程序修改关键 OS 数据。
- 当用户态程序需要访问关键资源的时候，可以通过 [syscall](#syscall) 来完成用户态程序与 OS 之间的互动。

### U-mode

处理器具有两种不同的模式：**用户模式**（U-mode）和**内核模式**（S-mode）：

- 在 S-mode 下，执行代码对底层硬件具有完整且不受限制的访问权限，它可以执行任何 CPU 指令（除了 M-mode 相关操作）并引用任何内存地址。
- 在 U-mode 下，执行代码无法直接访问硬件，必须委托给系统提供的接口才能访问硬件或内存。

处理器根据处理器上运行的代码类型在两种模式之间切换。应用程序以 U-mode 运行，而核心 OS 组件以 S-mode 运行。

### Syscall

**Syscall**（系统调用）是 U-mode 应用程序请求内核服务的一种方式。在 RISC-V 中，我们使用 `#!asm ecall` 指令进行 syscall。当在 U-mode 执行这条指令时，处理器会提升特权模式，跳转到异常处理函数（`stvec`）以处理这条 syscall。

Linux 中 RISC-V 相关的 syscall 可以在 [`include/uapi/asm-generic/unistd.h`](https://elixir.bootlin.com/linux/v5.15/source/include/uapi/asm-generic/unistd.h) 中找到。[syscall(2)](https://man7.org/linux/man-pages/man2/syscall.2.html) 手册页对 RISC-V 架构上的调用说明进行了总结，syscall 参数使用 `a0` \~ `a5`，syscall 号使用 `a7`，syscall 的返回值会被保存到 `a0` 与 `a1` 中。

在 RISC-V 平台上，syscall 与 SBI 调用类似，分别是应用程序与内核、内核与 OpenSBI 之间的接口：

- SBI 调用是内核（S-mode）与 OpenSBI（M-mode）之间的接口。S-mode 通过执行 `#!asm ecall` 指令产生 Environment call from S-mode 异常，特权态提升至 M-mode，跳转到 OpenSBI 的异常处理函数（`mtvec`）进行处理。处理完成后，OpenSBI 会通过 `#!asm mret` 指令返回到 S-mode。
- Syscall 是应用程序（U-mode）与内核（S-mode）之间的接口。U-mode 通过执行 `#!asm ecall` 指令产生 Environment call from U-mode 异常，特权态提升至 S-mode，跳转到内核的异常处理函数（`stvec`）进行处理。处理完成后，内核会通过 `#!asm sret` 指令返回到 U-mode。

### `sstatus.SUM` 与 `PTE.U`

当页表项 `PTE.U` 置 0 时，该页表项对应的内存页为内核页，运行在 U-mode 下的代码**无法访问**该页；类似的，当页表项 `PTE.U` 置 1 时，该页表项对应的内存页为用户页，运行在 S-mode 下的代码无法访问该页。如果想让 S-mode 下的程序能够访问用户页，需要将 `sstatus.SUM` 置 1。但是无论如何，用户页中的指令对于 S-mode 而言都是**无法执行**的。

### 用户态栈与内核态栈

当用户态程序在用户态运行时，其使用的栈为**用户态栈**；当进行 syscall 时，陷入内核处理时使用的栈为**内核态栈**。因此需要区分用户态栈和内核态栈，并在异常处理的过程中需要对栈进行切换。

## 实验步骤

此次实验基于 [Lab3](lab3.md) 同学们所实现的代码进行。

### 准备工程

```text linenums="1" hl_lines="4 6 8 12 18"
├── arch
│   └── riscv
│       ├── include
│       │   └── ksyscalls.h
│       └── kernel
│           └── ksyscalls.c
├── include
│   └── syscalls.h
└── user
    ├── Makefile
    ├── include
    │   └── unistd.h
    ├── src
    │   ├── Makefile
    │   ├── head.S
    │   ├── main.c
    │   ├── printf.c
    │   └── syscalls.c
    ├── uapp.S
    └── uapp.lds
```

`src/lab4` 的目录结构如上。请同学们将以上文件同步到 `project/kernel` 对应目录下。

在本次实验中，我们加入了用户态程序 `uapp`。`uapp` 的编译链接与内核代码独立进行。我们会将 strip 为纯二进制文件的用户态程序（`uapp.bin`，见后文）内嵌至 `vmlinux` 中，这种情况下用户程序运行的第一条指令位于二进制文件的开始位置，这个位置在内核中由 `_suapp` 符号标记。

同学们需要完成以下工作：

- 修改 `private_kdefs.h`，在适当的位置加入用户程序相关的宏定义：

    ```c title="arch/riscv/include/private_kdefs.h" linenums="0"
    #define USER_START 0x0        // user space start virtual address
    #define USER_END 0x4000000000 // user space end virtual address
    ```

- 按照如下 diff 修改 `arch/riscv/kernel/vmlinux.lds`，将用户态程序 `uapp` 加载至 `.data` 段。

    ```diff title="(diff) arch/riscv/kernel/vmlinux.lds" linenums="0"
    @@ -56,6 +56,12 @@
             *(.got .got.*)

             _edata = .;
    +
    +        . = ALIGN(0x1000);
    +        _suapp = .;
    +        *(.uapp .uapp*)
    +        _euapp = .;
    +        . = ALIGN(0x1000);
         } >ramv AT>ram

         .bss : ALIGN(0x1000) {
    ```

- 按照如下 diff 修改**顶层** `Makefile`，加入对 `user` 目录的编译支持以及将 `uapp` 相关的数据嵌入到 `vmlinux` 中。

    ```diff title="(diff) Makefile" linenums="0"
    @@ -20,7 +20,8 @@
     all:
     	$(MAKE) -C lib all
     	$(MAKE) -C arch/riscv all
    -	$(LD) -T arch/riscv/kernel/vmlinux.lds arch/riscv/kernel/*.o lib/*.o -o vmlinux
    +	$(MAKE) -C user all
    +	$(LD) -T arch/riscv/kernel/vmlinux.lds user/uapp.o arch/riscv/kernel/*.o lib/*.o -o vmlinux
     	mkdir -p arch/riscv/boot
     	$(OBJCOPY) -O binary vmlinux arch/riscv/boot/Image
     	$(OBJDUMP) -S vmlinux > vmlinux.asm
    @@ -55,6 +56,7 @@

     clean:
     	$(MAKE) -C lib clean
    +	$(MAKE) -C user clean
     	$(MAKE) -C arch/riscv clean
     	$(MAKE) -C "$(SNPRINTF_TEST_DIR)" -f "$(SNPRINTF_MAKEFILE)" clean
     	rm -rf vmlinux vmlinux.asm snprintf_test System.map arch/riscv/boot
    ```

- 在 `include/stdio.h` 中适当的位置加入 `printf` 的声明：

    ```c title="include/stdio.h" linenums="0"
    int printf(const char *restrict fmt, ...);
    ```

完成以上修改后，运行 `make` 即会生成 `user/uapp.o`、`user/uapp.elf` 和 `user/uapp.bin`。其中 `uapp.elf` 是从 `user/src` 目录中所有源文件编译得到的可执行文件，其会被 strip 得到纯二进制文件 `uapp.bin`。`uapp.S` 会通过 `#!asm .incbin` 指令将 `uapp.bin` 得到 `uapp.o`，后者被链接到内核中。这部分已经在 Makefile 中完成，大家只需要关注 `user/src` 目录下的文件。

!!! tip "调试小寄巧"

    与 [Lab3](lab3.md) 一样，由于用户程序运行在自己的地址空间中，且 `uapp.bin` 不含有调试信息，因此 GDB 无法进行源代码级别的调试。编译完成后 `user` 目录下会生成 `uapp.asm` 文件，该文件是 `uapp.elf` 的反汇编结果，大家可以结合该文件进行调试。

### 创建用户态进程

由于创建用户态进程要读取/设置 `sepc`、`sstatus`、`sscratch` 等 CSR，我们需要将它们加入 `thread_struct` 中。具体而言：

- `sepc`：保存 S-mode 中断处理完毕后 `#!asm sret` 的返回地址。
- `sstatus`：控制 S-mode 的状态寄存器，包含 `SUM`、`SPIE` 等重要标志位。
- `sscratch`：由 S-mode 自由设置。在我们的实验中，我们用其保存另一状态的 `sp`，在特权态切换时进行栈的更新。
- `scause`：保存异常原因。
- `stval`：根据不同的异常类型，保存不同的信息值。

另外，由于多个用户态进程需要保证相对隔离，因此不可以共用页表。每个用户态进程都需要创建独立的页表。

首先，修改 `arch/riscv/include/proc.h`，在适当的位置加入/修改如下代码：

```c title="arch/riscv/include/proc.h" linenums="0"
typedef uint64_t *pagetable_t;

// 中断处理所需寄存器堆
struct pt_regs {
  uint64_t x[32];
  uint64_t sepc;
};

// 线程状态结构
struct thread_struct {
  uint64_t ra;
  uint64_t sp;
  uint64_t s[12];

  uint64_t sepc;
  uint64_t sstatus;
  uint64_t sscratch;
  uint64_t stval;
  uint64_t scause;
};

// 进程数据结构
struct task_struct {
  uint64_t pid;      // 进程 ID
  uint64_t state;    // 状态
  uint64_t priority; // 优先级
  uint64_t counter;  // 剩余时间

  struct thread_struct thread; // 线程结构

  pagetable_t pgd; // 页表
};
```

然后在 `arch/riscv/kernel/proc.c` 中修改 `task_init`：

- 每个用户态进程拥有两个 stack：U-mode stack 以及 S-mode stack。其中 S-mode stack 就是当前已经实现的内核栈，U-mode stack 则是我们需要为每个用户态进程分配的栈，我们需要为其分配新的一页空间。
- 对于每个进程的 `task_struct`，我们需要初始化在 `thread_struct` 中添加的新成员变量。具体而言：
    - 将 `sepc` 初始化为 `USER_START`，即用户态程序的起始地址。
    - 在 `sstatus` 中正确设置：
        - `SPP` 位，使得 `sret` 能够返回到 U-mode。
        - `SPIE` 位，使得 `sret` 返回后开启中断。
        - `SUM` 位，使得 S-mode 可以访问用户页面。

        你可以设置任何其他你认为必要的标志位。

        !!! tip "你需要阅读 RISC-V 手册来搞清楚每个标志位的具体含义与具体值。"

    - `sscratch` 初始化为 U-mode stack，其值为 `USER_END`，即 U-mode stack 被放置在 user space 的最后一个页面。
    - `stval` 与 `scause` 置 0。

- 为每个用户进程创建自己的页表，并记录在 `task_struct` 中。记录的页表地址是物理地址还是虚拟地址可以自行决定，但在后续处理切换 `satp` 时需要注意保持一致。
    - 为了避免切换特权态时切换页表，你可以将内核页表 `swapper_pg_dir` 复制到每个进程的页表中。
    - 注意为 U-mode stack 创建对应的映射。

- 将 `uapp` 映射到每个进程的页表中。`uapp` 的起止地址由 `_suapp` 和 `_euapp` 符号标记。`arch/riscv/kernel/mm.h` 中提供了分配多个页的函数 `alloc_pages`，你可以使用该函数来分配连续的数页空间。

    注意，`uapp` 本身同样有 `.bss`、`.data` 等数据段，但这些信息在 `uapp` 被链接进 kernel 时丢失了，`uapp` 所有的数据是一块连续的内存区域。数据段不在栈上，而 `uapp` 的可执行代码会对这部分数据进行访问及修改，因此：

    - `uapp` 需要先被**复制**到一块进程专用的内存之后再进行映射，防止所有的进程都访问同一份 `uapp` 的数据段，造成数据混乱。
    - 你需要思考在这种情况下应该如何设置 PTE 的权限位。

最后在 `arch/riscv/kernel/entry.S` 中修改 `__switch_to`，需要加入切换新加入的 CSR 及页表的逻辑。在切换页表后，注意使用 `#!asm sfence.vma` 刷新 TLB。

可供参考的内存映射示意图如下所示：

```text linenums="0"
           PHY_START                                            PHY_END
              │      _suapp       _euapp                           │
              │         │            │                             │
              ↓         ↓            ↓                             ↓
  ┌───────────┬─────────┬────────────┬─────────────────────────────┐
PA│           │         │    uapp    │                             │
  └───────────┴─────────┴────────────┴─────────────────────────────┘
                        ↑            ↑
  ┌─────────────────────┘            │
  │                                  │
  │            ┌─────────────────────┘
  │            │
  │            │
  ├────────────┼─────────────────────────────────────────────┬──────────────┐
VA│    uapp    │                                             │ U-mode stack │
  └────────────┴─────────────────────────────────────────────┴──────────────┘
  ↑                                                                         ↑
  │                                                                         │
  │                                                                         │
USER_START                                                           USER_END
```

### 修改 `head.S` 及 `start_kernel`

之前的实验中所有线程都运行在 S-mode，因此在 OS 启动之后，我们将线程调度交给第一次时钟中断来完成。为引入用户态进程，我们需要修改这一逻辑，在 OS 启动完成后立即调度 `uapp` 运行。具体而言：

- 去除 `head.S` 中 `sstatus.SIE` 的设置逻辑。对 `sstatus` 的其他设置已经交给 `task_init` 来完成。
- 去除 `start_kernel` 中等待第一次时钟中断的逻辑，改为直接调用 `schedule` 函数进行调度。

### 修改中断逻辑及中断处理函数

与 ARM 架构不同，RISC-V 只有一个栈指针寄存器 `sp`，因此我们要手动处理 U-mode stack 与 S-mode stack 的切换。

由于我们的用户态进程运行在 U-mode 下，使用 U-mode stack，因此当触发异常时，我们首先要对栈进行切换（U-mode stack -> S-mode stack）。同理，当我们完成了异常处理，从 S-mode 返回至 U-mode，也需要进行栈切换（S-mode stack -> U-mode stack）。

我们需要修改 `__dummy`。在[创建用户态进程](#_7)中初始化进程结构时，`#!c thread_struct::sp` 保存 S-mode `sp`，`#!c thread_struct::sscratch` 保存 U-mode `sp`。回忆进程从 `__dummy` 开始运行，此时处于 S-mode，`sp` 指向 S-mode stack。现在我们需要在执行 `#!asm sret` 指令后特权态改变为 U-mode，因此需要在 `#!asm sret` 前交换对应的栈指针。

!!! tip ""

    在修改完 `__dummy` 后，原来的 `dummy_task` 函数就不再需要了。你可以将其删除。

我们需要修改 `_traps`。与 `__dummy` 类似，在进入和离开 `_traps` 时都需要切换栈。

`uapp` 执行 `#!asm ecall` 指令时会产生 Environment call from U-mode 异常，我们需要在 `trap_handler` 里面捕获之并进行处理。我们需要修改 `trap_handler`，新的函数签名如下：

```c
void trap_handler(struct pt_regs *regs, uint64_t scause, uint64_t stval) {
  /* ... */
}
```

其中 `scause` 和 `stval` 就是对应 CSR 的值，由 `_traps` 传递。这里需要解释第一个参数 `regs`。在 `_traps` 中，寄存器堆是**连续**地保存在 S-mode stack 上的，因此我们可以将这一段看做一个 `#!c struct pt_regs`，表示整个寄存器堆，其结构如下。我们可以在处理中断时直接使用该结构体来访问寄存器，在 C 代码中也能方便地对其进行操作。对 `regs` 成员的任何修改都会在 `_traps` 恢复上下文时生效。

```text linenums="0"
 High address ───►  ┌─────────────┐
                    │    sepc     │
                    │     x31     │
                    │     ...     │
                    │     ...     │
                    │      ..     │
                    │      x1     │
                    │      x0     │
    sp (regs)  ──►  ├──────┬──────┤
                    │      ▼      │
                    │             │
                    │             │
                    │             │
  Low address ───►  └─────────────┘
```

我们在[创建用户态进程](#_7)中给出了 `#!c struct pt_regs` 的一种实现方式，同学们可以根据自己的实现对其进行增改。注意在 `_traps` 中更新传递参数给 `trap_handler` 的逻辑。

另外注意，在 `trap_handler` 中处理完毕 Environment call from U-mode 异常后，需要将 `sepc` 加 4。

### 添加 syscall

我们在本次实验中会用到如下 2 个 syscall：

- 64 号 syscall [`sys_write`](https://elixir.bootlin.com/linux/v5.15/source/include/linux/syscalls.h#L503)。该调用将应用程序传递的字符串输出到对应的 `fd` 上。用例见 `user/printf.c`。
- 172 号 syscall [`sys_getpid`](https://elixir.bootlin.com/linux/v5.15/source/include/linux/syscalls.h#L782)。该调用从 `#!c struct task_struct *current` 中获取当前的 `pid` 放入 `a0` 中返回。用例见 `user/main.c`。

部分为实现 syscall 而加入的文件的用途如下：

- `include/syscalls.h`：定义了 syscall 号。这些 syscall 号可以由内核代码和用户代码共享，避免重复定义。
- `arch/riscv/include/ksyscalls.h`：声明了内核**处理** syscall 的函数。
- `arch/riscv/kernel/ksyscalls.c`：内核**处理** syscall 的实现。你需要完成这个文件。
- `user/include/unistd.h`：声明了用户态**调用** syscall 的函数。
- `user/src/syscalls.c`：用户态**调用** syscall 的实现。你需要完成这个文件。

!!! tip "实现提示"

    内核态代码位于 `arch/riscv` 目录下，用户态代码位于 `user` 目录下。如果你被文件结构搞糊涂了，可以参考思考题 5。

    在 Linux 中，`fd` 定义为一个非负 `#!c int`，表示进程所打开的某一个文件。0、1、2 分别对应 `stdin`、`stdout` 和 `stderr`。在本实验中，我们只需要实现 `fd = 1` 的情况，即将字符串输出到屏幕上。

### 编译及测试

由于加入了一些新的文件，可能需要修改一些 Makefile，请同学自己尝试修改，使项目可以编译并运行。样例输出如下，其中的额外输出可供参考，你的输出不需与其完全一致：

```text linenums="0" hl_lines="6-10 28 39 50 57-61"
OpenSBI v1.5
    ...
...buddy_init done! size = 32768
...task_init done!
2025 ZJU Computer System III
SET [PID = 1, PRIORITY = 5, COUNTER = 5]
SET [PID = 2, PRIORITY = 9, COUNTER = 9]
SET [PID = 3, PRIORITY = 3, COUNTER = 3]
SET [PID = 4, PRIORITY = 5, COUNTER = 5]
switch to [PID = 2, PRIORITY = 9, COUNTER = 9]
[S] Supervisor timer interrupt
[U] [PID = 2, sp = 0x3fffffffe0] i = 1 @ 552657
[S] Supervisor timer interrupt
[U] [PID = 2, sp = 0x3fffffffe0] i = 2 @ 1552703
[S] Supervisor timer interrupt
[U] [PID = 2, sp = 0x3fffffffe0] i = 3 @ 2552703
[S] Supervisor timer interrupt
[U] [PID = 2, sp = 0x3fffffffe0] i = 4 @ 3552703
[S] Supervisor timer interrupt
[U] [PID = 2, sp = 0x3fffffffe0] i = 5 @ 4552703
[S] Supervisor timer interrupt
[U] [PID = 2, sp = 0x3fffffffe0] i = 6 @ 5552703
[S] Supervisor timer interrupt
[U] [PID = 2, sp = 0x3fffffffe0] i = 7 @ 6552703
[S] Supervisor timer interrupt
[U] [PID = 2, sp = 0x3fffffffe0] i = 8 @ 7552703
[S] Supervisor timer interrupt
switch to [PID = 1, PRIORITY = 5, COUNTER = 5]
[U] [PID = 1, sp = 0x3fffffffe0] i = 1 @ 8503472
[S] Supervisor timer interrupt
[U] [PID = 1, sp = 0x3fffffffe0] i = 2 @ 9503541
[S] Supervisor timer interrupt
[U] [PID = 1, sp = 0x3fffffffe0] i = 3 @ 10503541
[S] Supervisor timer interrupt
[U] [PID = 1, sp = 0x3fffffffe0] i = 4 @ 11503541
[S] Supervisor timer interrupt
[U] [PID = 1, sp = 0x3fffffffe0] i = 5 @ 12503541
[S] Supervisor timer interrupt
switch to [PID = 4, PRIORITY = 5, COUNTER = 5]
[U] [PID = 4, sp = 0x3fffffffe0] i = 1 @ 13507271
[S] Supervisor timer interrupt
[U] [PID = 4, sp = 0x3fffffffe0] i = 2 @ 14507314
[S] Supervisor timer interrupt
[U] [PID = 4, sp = 0x3fffffffe0] i = 3 @ 15507324
[S] Supervisor timer interrupt
[U] [PID = 4, sp = 0x3fffffffe0] i = 4 @ 16507324
[S] Supervisor timer interrupt
[U] [PID = 4, sp = 0x3fffffffe0] i = 5 @ 17507324
[S] Supervisor timer interrupt
switch to [PID = 3, PRIORITY = 3, COUNTER = 3]
[U] [PID = 3, sp = 0x3fffffffe0] i = 1 @ 18507122
[S] Supervisor timer interrupt
[U] [PID = 3, sp = 0x3fffffffe0] i = 2 @ 19507161
[S] Supervisor timer interrupt
[U] [PID = 3, sp = 0x3fffffffe0] i = 3 @ 20507161
[S] Supervisor timer interrupt
SET [PID = 1, PRIORITY = 5, COUNTER = 5]
SET [PID = 2, PRIORITY = 9, COUNTER = 9]
SET [PID = 3, PRIORITY = 3, COUNTER = 3]
SET [PID = 4, PRIORITY = 5, COUNTER = 5]
switch to [PID = 2, PRIORITY = 9, COUNTER = 9]
```

## 思考题

1. 给出 GDB 的截图，证明你的 `uapp` 的确是运行在用户态下的。
2. 为什么内核 syscall 时，需要用 `#!c regs.a0` 来返回值给 `uapp`，而不能直接修改寄存器？
3. 在你的实现中将内核页表 `swapper_pg_dir` 复制到每个进程的页表中时用的是物理地址还是虚拟地址，为什么？
4. 考虑 `_traps` 在本次实验与之前实验的区别。现在，我们在进入和离开 `_traps` 都需要切换栈；这隐含一个条件，即 `_traps` 一定是从 U-mode 进入的，这是否正确？换个说法，如果 `_traps` 是从 S-mode 进入的，那么反倒不能切换栈了，我们需要加入额外的判断逻辑。我们应该如何处理，或者是否这种情况不可能发生？说明你的理由。

    - 更进一步地，**在之前的实验中**，我们完全不涉及 `_traps` 的栈切换，内核始终运行在 S-mode 下。那么**在本次实验中**，你认为是什么**最关键**的原因/更改导致 `_traps` 一定是从 U-mode 进入的？

    !!! tip "你需要结合 `sstatus` 的变化来分析。"

5. 对于 `user/src/main.c` 中的 `printf` 调用：

    ```c title="user/src/main.c" linenums="28"
    printf("\x1b[44m[U]\x1b[0m [PID = %d, sp = %p] i = %d @ %" PRIu64 "\n", getpid(), sp, ++i, prev_clock);
    ```

    请分析这一行的调用链，即从 `printf` 开始，到 `uapp` 执行 `#!asm ecall`，再到内核处理 syscall，最后返回到 `printf` 的整个过程。在你的实现中，这中间有哪些函数被以什么参数调用？

    !!! tip "提示"

        你可以搭配使用 GDB 来帮助你理解这一过程，必要时你可以附上 GDB 的截图。

        `printf` 的实现如下：

        ```c title="user/src/printf.c" linenums="0"
        static int printf_syscall_write(FILE *restrict fp, const void *restrict buf, size_t len) {
          (void)fp;
          return (int)write(STDOUT_FILENO, buf, len);
        }

        int printf(const char *restrict fmt, ...) {
          va_list ap;
          va_start(ap, fmt);
          int ret = vfprintf(stdout, fmt, ap);
          va_end(ap);
          return ret;
        }
        ```

        注意到了吗？这与我们目前内核 `printk` 的实现非常类似。你不需要深入 `vfprintf` 的实现，在回答本问题时可以简略为 `vfprintf` -> `printf_syscall_write`。不过，如果你对其中的细节感兴趣，可以参考 [Sys2 Bonus 实验](https://zju-sys.pages.zjusct.io/sys2/sys2-fa24/bonus/)，其中包含许多有用的信息。

## 实验提交

同学需要提交实验报告，以及 `project/kernel` 目录下编写的所有代码文件。

**提交前请使用 `make clean` 清除所有构建产物。**
