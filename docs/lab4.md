<style>
code {
    font-family: 'Cascadia', SFMono-Regular, Consolas, Menlo, monospace;
}
</style>

# 实验 4：RV64 用户模式

!!! info "计划 24.05.02 发布、24.05.21 截止验收与提交（两周，考虑到五一假期，暂定延迟五天）"

## 实验目的

* 创建用户态进程，并设置 `sstatus` 来完成内核态转换至用户态。
* 正确设置用户进程的**用户态栈**和**内核态栈**， 并在异常处理时正确切换。
* 补充异常处理逻辑，完成指定的系统调用（SYS_WRITE, SYS_GETPID）功能。

## 实验环境

* 与前一实验一致

## 背景知识

在 [Lab3](../lab3) 中，我们开启虚拟内存，这为进程间地址空间相互隔离打下了基础。之前的实验中我们只创建了内核进程，他们共用了地址空间（共用一个**内核页表** `swapper_pg_dir`）。在本次实验中我们将引入用户态进程：

* 当启动用户模式应用程序时，内核将为该应用程序创建一个进程，为应用程序提供了专用虚拟地址空间等资源。
* 因为应用程序的虚拟地址空间是私有的，所以一个应用程序无法更改属于另一个应用程序的数据。
* 每个应用程序都是独立运行的，如果一个应用程序崩溃，其他应用程序和操作系统不会受到影响。
* 同时，用户模式应用程序可访问的虚拟地址空间也受到限制，在用户模式下无法访问内核的虚拟地址，防止应用程序修改关键操作系统数据。
* 当用户态程序需要访问关键资源的时候，可以通过[系统调用](#系统调用约定)来完成用户态程序与操作系统之间的互动。

### 用户模式基础介绍

处理器具有两种不同的模式：**用户模式**（U-Mode）和**内核模式**（S-Mode）：

* 在内核模式下，执行代码对底层硬件具有完整且不受限制的访问权限，它可以执行任何 CPU 指令并引用任何内存地址。
* 在用户模式下，执行代码无法直接访问硬件，必须委托给系统提供的接口才能访问硬件或内存。

处理器根据处理器上运行的代码类型在两种模式之间切换。应用程序以用户模式运行，而核心操作系统组件以内核模式运行。

### 系统调用约定

**系统调用**是用户态应用程序请求内核服务的一种方式。在 RISC-V 中，我们使用 `ecall` 指令进行系统调用。当执行这条指令时，处理器会提升特权模式，跳转到异常处理函数以处理这条系统调用。

Linux 中 RISC-V 相关的系统调用可以在 [`include/uapi/asm-generic/unistd.h`](https://elixir.bootlin.com/linux/v5.15/source/include/uapi/asm-generic/unistd.h) 中找到，[syscall(2)](https://man7.org/linux/man-pages/man2/syscall.2.html) 手册页上对RISC-V架构上的调用说明进行了总结，系统调用参数使用 `a0` - `a5`，系统调用号使用 `a7`， 系统调用的返回值会被保存到 `a0` 与 `a1` 中。

### sstatus[SUM] 与 PTE[U]

当页表项 PTE[U] 置 0 时，该页表项对应的内存页为内核页，运行在 U-Mode 下的代码**无法访问**该页；类似的，当页表项 PTE[U] 置 1 时，该页表项对应的内存页为用户页，运行在 S-Mode 下的代码**无法访问**该页。如果想让 S-Mode 下的程序能够访问用户页，需要将 sstatus[SUM] 位置 1。但是无论什么样的情况下，用户页中的指令对于 S-Mode 而言都是**无法执行**的。

### 用户态栈与内核态栈

当用户态程序在用户态运行时，其使用的栈为**用户态栈**；当进行系统调用时，陷入内核处理时使用的栈为**内核态栈**。因此需要区分用户态栈和内核态栈，并在异常处理的过程中需要对栈进行切换。

## 实验步骤

此次实验基于 [Lab3](../lab3) 同学们所实现的代码进行。

### 准备工程

* 需要修改 `vmlinux.lds`，将用户态程序 `uapp` 加载至 `.data` 段。按如下修改，其余部分保持不变：
    ```asm
    ...
    .data : ALIGN(0x1000){
        _sdata = .;

        *(.sdata .sdata*)
        *(.data .data.*)

        _edata = .;

        . = ALIGN(0x1000);
        uapp_start = .;
        *(.uapp .uapp*)
        uapp_end = .;
        . = ALIGN(0x1000);

    } >ramv AT>ram
    ...
    ```
* 需要修改 `defs.h`，在 `defs.h` `添加` 如下内容：
    ```c
    #define USER_START (0x0000000000000000) // user space start virtual address
    #define USER_END   (0x0000004000000000) // user space end virtual address
    ```
* 从 `repo` 同步以下内容，并按照文件结构将这些文件正确放置。
    ```
    src/lab4
    ├── arch
    │   └── riscv
    │       ├── include
    │       │   └── mm.h
    │       ├── kernel
    │       │   └── mm.c
    │       └── Makefile
    └── user
        ├── getpid.c
        ├── link.lds
        ├── Makefile
        ├── printf.c
        ├── start.S
        ├── stddef.h
        ├── stdio.h
        ├── syscall.h
        └── uapp.S
    ```
    其中，我们在 `mm` 中添加了 `buddy system`，并保证了原来调用的 `kalloc` 和 `kfree` 的兼容。同学们无需修改原先使用了 `kalloc` 的相关代码。
    ``` c
    // 分配 page_cnt 个页的地址空间，返回分配内存的地址。保证分配的内存在虚拟地址和物理地址上都是连续的
    uint64_t alloc_pages(uint64_t page_cnt);
    // 相当于 alloc_pages(1);
    uint64_t alloc_page();
    // 释放从 addr 开始的之前按分配的内存
    void free_pages(uint64_t addr);
    ```
* 修改**根目录**下的 `Makefile`，将 `user` 纳入工程管理，在适当位置添加如下内容：
    ``` Makefile
    ${MAKE} -C user all
    ${MAKE} -C user clean
    ```
* 在根目录下 `make` 会生成 `user/uapp.o`, `user/uapp.elf`, `user/uapp.bin`。通过 `riscv64-linux-gnu-objdump` 我们可以看到 uapp 使用 ecall 来进行系统调用(在 U-Mode 下使用 ecall 会触发 environment-call-from-U-mode 异常)，从而将控制权交给处在 S-Mode 的 OS，由内核来处理相关异常。
    ```bash
    $ riscv64-linux-gnu-objdump -d user/uapp.elf
    0000000000000004 <getpid>:
     4:   fe010113                addi    sp,sp,-32
     8:   00813c23                sd      s0,24(sp)
     c:   02010413                addi    s0,sp,32
    10:   fe843783                ld      a5,-24(s0)
    14:   0ac00893                li      a7,172
    18:   00000073                ecall                   <- SYS_GETPID                       
    ...

    00000000000000dc <vprintfmt>:
    ...
    610:   00070513                mv      a0,a4
    614:   00068593                mv      a1,a3
    618:   00060613                mv      a2,a2
    61c:   00000073                ecall                   <- SYS_WRITE
    ...
    ```
* 在本次实验中，我们仅会将 strip 成纯二进制文件 `user/uapp.bin` 作为用户态程序进行运行。在这种情况下，用户程序运行的第一条指令位于二进制文件的开始位置, 也就是说 `_uapp_start` 处的指令就是我们要执行的第一条指令。你可以使用 `extern char uapp_start[];` 来引用这个地址。


### 创建用户态进程

本次实验只需要创建 3 个用户态进程，修改 `proc.h` 中的 `NR_TASKS` 为 `1 + 3`。

由于创建用户态进程要对 `sepc`, `sstatus`, `sscratch` 做设置，我们将其加入 `thread_struct` 中。此外，增加一些其他的 CSR 寄存器 `stval` `scause`，方便后续实验使用。

* `sepc`：保存特权态中断处理完毕后 `sret` 的返回地址。
* `sstatus`：控制信号，控制当前是否中断。
* `sscratch`：保存另一个状态的 `sp`，用于在切换状态时更新 `sp`。
* `stval`：保存导致异常的指令地址。
* `scause`：保存导致异常的原因。

由于多个用户态进程需要保证相对隔离，因此不可以共用页表。我们为每个用户态进程都创建一个页表。修改 `task_struct` 如下：
```c
// proc.h 

typedef unsigned long* pagetable_t;

struct thread_struct {
    uint64 ra;
    uint64 sp;
    uint64 s[12];

    uint64 sepc;
    uint64 sstatus;
    uint64 sscratch;
    uint64 stval;
    uint64 scause;
};

struct task_struct {
    uint64 state;
    uint64 counter;
    uint64 priority;
    uint64 pid;

    struct thread_struct thread;

    pagetable_t pgd;
};
```

修改 task_init:

* 对每个用户态进程，其拥有两个 stack：U-Mode Stack 以及 S-Mode Stack，其中 S-Mode Stack 在[系统二实验五](https://zju-sys.pages.zjusct.io/sys2/sys2-fa23/lab5/)中我们已经设置好了。我们可以通过 `alloc_page` 接口申请一个空的页面来作为 U-Mode Stack。
* 对于每个进程，初始化我们刚刚在 `thread_struct` 中添加的五个变量。具体而言：
    * 将 `sepc` 初始化为 `USER_START`，即用户态程序的起始地址。
    * 在 `sstatus` 中，初始化 `SPP` 为 U-Mode 对应的内容（`sret` 返回到 U-Mode），`SPIE` 为 `1`（`sret` 返回后开启中断），`SUM` 为 `1`（S-Mode 可以访问用户页面）。
    * `sscratch` 初始化为 U-Mode 的 `sp`，其值为 `USER_END`（即 U-Mode Stack 被放置在 user space 的最后一个页面）。
    * `stval` 与 `scause` 初始化为 `0` 即可。
* 为每个用户态进程创建自己的页表。写入 `task_struct` 中的页表地址可以是物理地址，也可以是虚拟地址，不过需要在后续的处理中需要注意获取正确的地址。注意映射上面步骤中申请的栈所在的页面。
* 为了避免 U-Mode 和 S-Mode 切换的时候切换页表，我们将内核页表 `swapper_pg_dir` 复制到每个进程的页表中。
* 将 `uapp`（用户态运行程序）所在的页面映射到每个进行的页表中。注意，在程序运行过程中可能有部分数据不在栈上，而在初始化的过程中就已经被分配了空间（本实验中没有这种情况，但是后续会涉及）。所以，二进制文件需要先被**拷贝**到一块某个进程专用的内存之后再进行映射，防止所有的进程共享数据，造成预期外的进程间相互影响。

最后，修改 `__switch_to`，需要加入切换添加的 CSR 寄存器以及切换页表的逻辑。在切换页表后，注意使用 `fence.i` 和 `vma.fence` 刷新 TLB 和 iCache。

可供参考的内存映射示意图如下所示：
```text
                PHY_START                                                                PHY_END
                   │     uapp_start   uapp_end                                              │
                   │         │            │                                                 │
                   ↓         ↓            ↓                                                 ↓
       ┌───────────┬─────────┬────────────┬─────────────────────────────────────────────────┐
 PA    │           │         │    uapp    │                                                 │
       └───────────┴─────────┴────────────┴─────────────────────────────────────────────────┘
                             ↑            ↑
       ┌─────────────────────┘            │
       │                                  │
       │            ┌─────────────────────┘
       │            │
       │            │
       ├────────────┼───────────────────────────────────────────────────────────────────┬────────────┐
 VA    │    uapp    │                                                                   │u mode stack│
       └────────────┴───────────────────────────────────────────────────────────────────┴────────────┘
       ↑                                                                                             ↑
       │                                                                                             │
       │                                                                                             │
   USER_START                                                                                    USER_END
```

!!! tip "关于 thread_info"
    在 `thread_info` 在后续实验中并不会再被使用，可以将其删除，但是注意在 `__switch_to` 中对位置的计算需要进行相应的修改。

### 修改中断逻辑以及中断处理函数

与 ARM 架构不同的是，RISC-V 中只有一个栈指针寄存器(sp)，因此需要我们来完成用户栈与内核栈的切换。

由于我们的用户态进程运行在 U-Mode 下，使用的运行栈也是 U-Mode Stack，因此当触发异常时，我们首先要对栈进行切换（U-Mode Stack -> S-Mode Stack）。同理，当我们完成了异常处理，从 S-Mode 返回至 U-Mode，也需要进行栈切换（S-Mode Stack -> U-Mode Stack）。

修改 `__dummy`。在 [创建用户态进程](#创建用户态进程) 中我们初始化时，`thread_struct.sp` 保存了 S-Mode `sp`，`thread_struct.sscratch` 保存了 U-Mode `sp`， 因此在用户进程一开始被调度时（一开始用户进程会从 `__dummy` 开始运行，此时处于 `S-Mode`，`sret` 后会进入 U-Mode），我们只需要交换对应的寄存器的值即可。

修改 `_traps`。同理在 `_traps` 的首尾我们都需要做与上一步类似的交换栈的操作。

!!! Warning "关于内核进程"
    需要注意，如果是内核进程（没有 U-Mode Stack）触发了异常，则不需要进行切换。需要在 `_traps` 的首尾都对此情况进行判断。（内核进程的 `sp` 永远指向的 S-Mode Stack， `sscratch` 为 0）

`uapp` 使用 `ecall` 会产生 environment-call-from-U-mode 异常，因此我们需要在 `trap_handler` 里面进行捕获。修改 `trap_handler` 如下：
```c
void trap_handler(uint64 scause, uint64 sepc, struct pt_regs *regs) {
    ...
}
```
这里需要解释新增加的第三个参数 `regs`。在 `_traps` 中，我们将寄存器的内容**连续**的保存在 S-Mode Stack 上， 因此我们可以将这一段看做一个叫做 `pt_regs` 的结构体。我们可以从这个结构体中取到相应的寄存器的值（比如 `syscall` 中我们需要从 `a0` ~ `a7` 寄存器中取到参数）。一个示例如下：
```
    High Addr ───►  ┌─────────────┐
                    │     sepc    │
                    │             │
                    │     x31     │
                    │             │
                    │      .      │
                    │      .      │
                    │      .      │
                    │             │
                    │     x1      │
                    │             │
                    │     x0      │
 sp (pt_regs)  ──►  ├─────────────┤
                    │             │
                    │             │
                    │             │
                    │             │
                    │             │
                    │             │
                    │             │
                    │             │
                    │             │
    Low  Addr ───►  └─────────────┘
```
同学们可以根据自己在 `_traps` 中实现的寄存器与各 CSR 寄存器的存储方式定义 `struct pt_regs`（可以在新增加的 `syscall.h` 文件中定义，见[添加系统调用](#添加系统调用)），并在 `trap_hanlder` 中补充处理系统调用的逻辑。

### 添加系统调用

本次实验要求的系统调用函数原型以及具体功能如下：

* 64 号系统调用 [`sys_write(unsigned int fd, const char *buf, size_t count)`](https://elixir.bootlin.com/linux/v5.15/source/include/linux/syscalls.h#L503)。该调用将用户态传递的字符串打印到屏幕上，此处 `fd` 为标准输出 `1`，`buf` 为用户需要打印的内容的起始地址，`count` 为字符串长度，返回打印的字符数。具体使用可见 `user/printf.c`。
* 172 号系统调用 [`sys_getpid()`](https://elixir.bootlin.com/linux/v5.15/source/include/linux/syscalls.h#L782) 该调用不接收参数，从 `current` 进程中获取当前的 `pid` 放入 `a0` 中返回。具体使用可见 `user/getpid.c`。
    
增加 `syscall.c`, `syscall.h` 文件， 并在其中实现 `getpid` 以及 `write` 逻辑。系统调用的返回参数应放置在参数 `regs` 中保存的 `a0` 中，而不可以直接修改寄存器。另外，针对系统调用这一类异常，我们需要手动将 `sepc + 4` 。

### 修改 head.S 以及 start_kernel

之前的实验中， 在 OS boot 之后，我们需要等待一个时间片，才会进行调度。我们现在更改为 OS boot 完成之后立即调度 `uapp` 运行，即设置好第一次时钟中断后，在 `main` 中直接调用 `schedule`：

* 在 `start_kernel` 中调用 `schedule`，并注意放置在 `test` 之前。
* 将 `head.S` 中 enable interrupt `sstatus.SIE` 的逻辑注释。

### 编译及测试

由于加入了一些新的文件，可能需要修改一些 Makefile 文件。请同学自己尝试修改，使项目可以编译并运行。一个输出示例如下：
```bash
OpenSBI v0.9
...
Boot HART MIDELEG         : 0x0000000000000222
Boot HART MEDELEG         : 0x000000000000b109
...buddy_init done!
...proc_init done!
2024 ZJU Computer System III
[S-MODE] SET [PID = 3 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[U-MODE] pid: 1, sp is 0000003fffffffe0
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U-MODE] pid: 2, sp is 0000003fffffffe0
[U-MODE] pid: 2, sp is 0000003fffffffe0
[S-MODE] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[U-MODE] pid: 3, sp is 0000003fffffffe0
[U-MODE] pid: 3, sp is 0000003fffffffe0
[U-MODE] pid: 3, sp is 0000003fffffffe0
[S-MODE] SET [PID = 3 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U-MODE] pid: 2, sp is 0000003fffffffe0
[U-MODE] pid: 2, sp is 0000003fffffffe0
[S-MODE] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[U-MODE] pid: 3, sp is 0000003fffffffe0
[U-MODE] pid: 3, sp is 0000003fffffffe0
```

## 思考题

1. 我们在实验中使用的用户态线程和内核态线程的对应关系是怎样的？即，是一对一，一对多，多对一还是多对多？
2. 为什么系统调用返回时，需要向 `regs` 中保存的 `a0` 中放置返回值，而不可以直接修改寄存器？
3. 为什么需要将 `head.S` 中 enable interrupt `sstatus.SIE` 逻辑注释？
4. 在你的实现中，写入 `task_struct` 中的页表地址是物理地址还是虚拟地址？将内核页表 `swapper_pg_dir` 复制到每个进程的页表中时又用的是物理地址还是虚拟地址，为什么？

## 实验提交

请在学在浙大上提交以下两份文件：

- 实验报告（pdf）
- 软件部分全部代码压缩包（打包前 `make clean` 清除编译产物）
