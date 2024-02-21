# 实验 7：实现 RV64 fork 机制

## 实验目的

* 为进程加入 **fork** 机制，能够支持通过 **fork** 创建新的用户态进程。

## 实验环境 

* 与前一实验一致

## 背景知识

### fork 系统调用

`fork` 是 Linux 中的重要系统调用，它的作用是将进行了该系统调用的 task 完整地复制一份，并加入 Ready Queue。这样在下一次调度发生时，调度器就能够发现多了一个 task，从这时候开始，新的 task 就可能被正式从 Ready 调度到 Running，而开始执行了。需留意，fork 具有以下特点：
* `fork` 通过复制当前进程创建一个新的进程，新进程称为子进程，而原进程称为父进程。
* 子进程和父进程在不同的内存空间上运行。
* 父进程 `fork` 成功时返回子进程的 PID，子进程返回 `0`；失败时，父进程返回 `-1`。
* 创建的子 task 需要深拷贝 `task_struct`，调整自己的页表、栈和 CSR 寄存器等信息，复制一份在用户态会用到的内存信息（用户态的栈、程序的代码和数据等），并且将自己伪装成是一个因为调度而加入了 Ready Queue 的普通程序来等待调度。在调度发生时，这个新 task 就像是原本就在等待调度一样，被调度器选择并调度。
* Linux 中使用了 `copy-on-write` 机制，`fork` 创建的子进程首先与父进程共享物理内存空间，直到父子进程有修改内存的操作发生时再为子进程分配物理内存。本次实验中将实现一个简单的 COW 机制。

### fork 在 Linux 中的实际应用

Linux 的另一个重要系统调用是 `exec`，它的作用是将进行了该系统调用的 task 换成另一个 task 。这两个系统调用一起，支撑起了 Linux 处理多任务的基础。当我们在 shell 里键入一个程序的目录时，shell（比如 zsh 或 bash）会先进行一次 fork，这时候相当于有两个 shell 正在运行。然后其中的一个 shell 根据 fork 的返回值（是否为 0），发现自己和原本的 shell 不同，再调用 exec 来把自己给换成另一个程序，这样 shell 外的程序就得以执行了。

## 实验步骤

### 准备工作

* 此次实验基于 Lab6 同学所实现的代码进行。
* 从 repo 同步以下文件夹: user 并按照以下步骤将这些文件正确放置。
    ```bash
    lab7
    ├── arch
    │   └── riscv
    │       ├── include
    │       │   └── mm.h
    │       └── kernel
    │           └── mm.c
    └── user
        └── getpid.c
    ```
* 在 `user/getpid.c` 中有四个 `main` 函数，在不同程度上检测同学们实现的 fork 功能是否正确。同学们可以通过启用不同的 `main` 函数来测试阶段性功能是否正确实现。
* 新提供的 `mm` 提供了用于对页面引用计数的接口，从而方便同学们实现 `fork` 时的页面共享机制。新定义的内容如下：
    ```c
    uint64 get_page(uint64 va); // 通过虚拟地址增加页面引用计数
                                // 成功返回 0，失败返回 1
    void put_page(uint64 va);   // 通过虚拟地址减少页面引用计数
    ```
  逻辑不算复杂，同学们可以参考 `mm.c` 中的实现进行理解。其中 `ref_cnt` 用于记录页面的引用计数，`page_ref_inc` 和 `page_ref_dec` 函数分别用于增加和减少页面的引用计数。
* 在 `proc.c` 中修改 `task_init` 函数中修改为仅初始化一个进程，之后其余的进程均通过 `fork` 创建。
* 在 [Lab4](../lab4) 中，我们曾经提及 RISC-V Sv39 模式的页表项：
    ```text
    63       54 53        28 27        19 18        10 9   8 7 6 5 4 3 2 1 0
    ┌──────────┬────────────┬────────────┬────────────┬─────┬─┬─┬─┬─┬─┬─┬─┬─┐
    │ Reserved │   PPN[2]   │   PPN[1]   │   PPN[0]   │ RSW │D│A│G│U│X│W│R│V│
    └──────────┴────────────┴────────────┴────────────┴─────┴─┴─┴─┴─┴─┴─┴─┴─┘
                                                        │   │ │ │ │ │ │ │ │
                                                        │   │ │ │ │ │ │ │ └──── V - Valid
                                                        │   │ │ │ │ │ │ └────── R - Readable
                                                        │   │ │ │ │ │ └──────── W - Writable
                                                        │   │ │ │ │ └────────── X - Executable
                                                        │   │ │ │ └──────────── U - User
                                                        │   │ │ └────────────── G - Global
                                                        │   │ └──────────────── A - Accessed
                                                        │   └────────────────── D - Dirty (0 in page directory)
                                                        └────────────────────── Reserved for supervisor software
    ```
  其中第 8-9 位为保留位，并未被使用。这意味着我们可以通过软件的方式来使用这两位。在本次实验中，我们可以使用其中一位来标记页面是否为共享页面。例如，我们可以在 `defs.h` 中添加如下的定义：
    ```c
    #define PTE_S 0x100
    ```
* 由于在实验过程中需要 fork 比较多的进程，因此需要修改 `NR_TASKS` 至少为 9 (1 + 8)。
* 为了方便实验中深拷贝页表，推荐同学们写一个 `walk_page_table` 的函数，用于遍历页表，找到对应的页表项。

### 实现 fork

#### 添加 fork 相关声明与定义

`fork` 所调用的 syscall 为 `SYS_CLONE`，系统调用号为 220。在 `syscall.h` 中添加如下内容：
```c
#define SYS_CLONE 220
```

在 `syscall.c` 中添加实现 `clone` 函数的相关代码如下。为了简单起见 `clone` 只接受一个参数 `pt_regs *`。
```c
uint64 do_fork(struct pt_regs *regs) {
	...
}

uint64 clone(struct pt_regs *regs) {
    return do_fork(regs);
}
```

接下来我们将尽力实现 `do_fork` 函数。

#### 拷贝内核态进程状态

我们先前提及，`fork` 的目标是父进程完整地复制一份，从而得到一个子进程。牢记这个目标，那门我们需要考虑的复制内容就很显然了：都在 `task_struct` 中：
```c
struct task_struct {
    uint64 state;
    uint64 counter;
    uint64 priority;
    uint64 pid;

    struct thread_struct thread;

    pagetable_t pgd;

    struct mm_struct *mm;
};
```
我们采用自顶向下的思想，先来处理内核态的状态。

回忆一下我们是怎样使用 `task_struct` 的，我们并不是分配了一块刚好大小的空间，而是分配了一整个页，并将页的高处作为了 task 的内核态栈：
```text
                    ┌─────────────┐◄─── High Address
                    │             │
                    │    stack    │
                    │             │
                    │             │
              sp ──►├──────┬──────┤
                    │      │      │
                    │      ▼      │
                    │             │
                    │             │
                    │             │
                    │             │
    4KB Page        │             │
                    │             │
                    │             │
                    │             │
                    ├─────────────┤
                    │             │
                    │             │
                    │ task_struct │
                    │             │
                    │             │
                    └─────────────┘◄─── Low Address
```
这意味着，内核态的所有数据、状态都包含在了这一页中，很大程度上简化了我们的实验。同学们只需要深拷贝一份这页的内容，并修改一些与新进程相关的内容即可；至于页表和内存管理的内容，我们会在后面的步骤中处理。**一些**需要提醒的修改内容如下：
* 选择一个空闲的 PID 作为子进程的 PID，将其放置到 `task` 数组中
* 时间片设置为 0 即可，等待调度器重新分配
* 当子进程被调度时，`__switch_to` 会从子进程的 `thread` 等成员变量中取出在 `do_fork` 中设置好的成员变量，并装载到寄存器中，因此需要正确设置 `thread` 结构体的内容：
  * 设置 `thread.ra` 为 `ret_from_fork`（详见[设置子进程返回逻辑](#设置子进程返回逻辑)）
  * 设置 `thread.sp` 为子进程的内核栈 `sp`（可以根据父进程 `task_struct` 地址、父进程 `sp` 与子进程 `task_struct` 地址计算得到）
* 在 `ret_from_fork` 中，我们将会根据内核栈中保存的 `pt_regs` 中对寄存器状态进行恢复。同学们可以考虑子进程的返回值 `a0`、栈指针、返回地址等内容。

#### 拷贝用户态进程状态

抽丝剥茧，我们现在剩下的主要任务就是处理子进程在用户态下的页表和内存管理了。

先从比较简单的内存管理开始吧。我们知道，子进程的内存管理结构 `mm` 是父进程的深拷贝，因此我们只需要**深拷贝**一份父进程的 `mm` 即可。请注意，这是一个**链表**，同学们需要正确地处理链表的深拷贝。

接着，让我们处理页表的拷贝。为了能在内核态正确运行，分配一个页给根页表后，复制内核根页表 `swapper_pg_dir` 必不可少。接下来，我们需要让用户态程序能够正确的找到虚拟地址对应的物理地址。如果我们不需要实现 COW 机制，那么我们只需要通过遍历 `mm` 中保存的 `vma`，将每个已经在父进程中映射的页在子进程中拷贝并映射即可。而为了实现 COW 机制，在此处，只需要将拷贝的过程修改为：使用 `get_page` 函数增加页面引用计数，然后将页表项的写位清除、共享位（如上定义的 `PTE_S`）置位。当然，也请别忘了在这之后对子页表映射。

!!! Warning "刷新 TLB"
    在前面的过程中，我们更改了页表项的 permission。在这之后，一个刷新 TLB 的操作是不可缺少的。你可以使用 `sfence.vma` 指令来刷新 TLB。

#### 设置父进程返回值

在 `do_fork` 中，我们需要设置父进程的返回值，即子进程的 PID。

至此，`do_fork` 的实现就完成了，父进程应该可以使用 `fork` 获得子进程的 PID 了。不过，子进程尚且不能运行，其返回逻辑还需要我们稍加处理。

#### 设置子进程返回逻辑

在实际动手之前，让我们先考虑一下父进程与子进程二者的返回路径。对于父进程而言，该路径为 `do_fork->clone->trap_handler->_traps->user program`；而通过上面的实现，我们知道，子进程的返回路径为 `__switch_to->ret_from_fork->...->user program`。那么很显然，`ret_from_fork` 与 `_traps` 有着很密切的关系。再仔细想想，子进程既然是父进程状态的复制，那么对于子进程而言，它是不是也像父进程从 `trap_handler` 中返回一样，认为自己是刚执行完一个系统调用呢？

这样的话，需要进行的工作就比较显然了。利用 `__switch_to` 时恢复的 `ra` 与 `sp`，我们可以实现一个类似于 ROP (return oriented programming) 的操作，跳转到 `_traps` 中从 `trap_handler` 返回的位置：
```asm
    ...
    jal ra, trap_handler

    .globl ret_from_fork
ret_from_fork:
    ...
```
这样，子进程就可以像父进程一样，从 `trap_handler` 返回，继续执行用户程序了。

#### 添加新的 Page Fault 处理

还记得我们删除了页表项的写权限吗？这意味着，当父子线程中有一个线程试图写入一个共享页面时，会触发一个页错误。我们需要在 `do_page_fault` 中添加对这种情况的处理。当发生这种情况时，我们需要为该进程分配一个新的页面，将原页面的内容拷贝到新页面中，并将新页面进行映射。对于原先的页面，别忘了使用 `put_page` 减少页面引用计数哦。

### 编译及测试

由于测试函数较多，我们在这里只给出第三个 `main` 函数的示例，其他的请同学们根据运行逻辑检查是否正确实现。这里需要同学们在 COW 发生时打印一些信息，以便于检查 COW 是否正确实现。

```bash
OpenSBI v0.9
...
...buddy_init done!
...proc_init done!
2024 ZJU Computer System III
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[U] pid: 1 is running! global_variable: 0
[S-MODE] PID = 1, Copy on Write on page 0000003ffffff000
[S-MODE] PID = 1, Copy on Write on page 0000003ffffff000
[S-MODE] PID = 1, Copy on Write on page 0000000000000000
[U] pid: 1 is running! global_variable: 1
[S-MODE] PID = 1, Copy on Write on page 0000003ffffff000
[S-MODE] PID = 1, Copy on Write on page 0000000000000000
[U] pid: 1 is running! global_variable: 2
[S-MODE] SET [PID = 4 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 3 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[S-MODE] PID = 2, Copy on Write on page 0000003ffffff000
[S-MODE] PID = 2, Copy on Write on page 0000003ffffff000
[S-MODE] PID = 2, Copy on Write on page 0000000000000000
[U] pid: 2 is running! global_variable: 1
[S-MODE] PID = 2, Copy on Write on page 0000003ffffff000
[S-MODE] PID = 2, Copy on Write on page 0000000000000000
[U] pid: 2 is running! global_variable: 2
[U] pid: 2 is running! global_variable: 3
[S-MODE] switch to [PID = 4, COUNTER = 4, PRIORITY = 4]
[S-MODE] PID = 4, Copy on Write on page 0000003ffffff000
[S-MODE] PID = 4, Copy on Write on page 0000000000000000
[U] pid: 4 is running! global_variable: 2
[U] pid: 4 is running! global_variable: 3
[S-MODE] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[S-MODE] PID = 3, Copy on Write on page 0000003ffffff000
[S-MODE] PID = 3, Copy on Write on page 0000000000000000
[U] pid: 3 is running! global_variable: 1
[S-MODE] PID = 3, Copy on Write on page 0000003ffffff000
[S-MODE] PID = 3, Copy on Write on page 0000000000000000
[U] pid: 3 is running! global_variable: 2
[U] pid: 3 is running! global_variable: 3
[S-MODE] SET [PID = 7 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 6 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 5 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 4 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 3 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[U] pid: 1 is running! global_variable: 3
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U] pid: 2 is running! global_variable: 4
[S-MODE] switch to [PID = 4, COUNTER = 4, PRIORITY = 4]
[U] pid: 4 is running! global_variable: 4
[S-MODE] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[U] pid: 3 is running! global_variable: 4
[U] pid: 3 is running! global_variable: 5
[S-MODE] switch to [PID = 5, COUNTER = 5, PRIORITY = 5]
[S-MODE] PID = 5, Copy on Write on page 0000003ffffff000
[S-MODE] PID = 5, Copy on Write on page 0000000000000000
[U] pid: 5 is running! global_variable: 1
[S-MODE] PID = 5, Copy on Write on page 0000003ffffff000
[S-MODE] PID = 5, Copy on Write on page 0000000000000000
[U] pid: 5 is running! global_variable: 2
[U] pid: 5 is running! global_variable: 3
[S-MODE] switch to [PID = 6, COUNTER = 5, PRIORITY = 5]
[S-MODE] PID = 6, Copy on Write on page 0000003ffffff000
[S-MODE] PID = 6, Copy on Write on page 0000000000000000
[U] pid: 6 is running! global_variable: 2
[U] pid: 6 is running! global_variable: 3
[S-MODE] switch to [PID = 7, COUNTER = 5, PRIORITY = 5]
[S-MODE] PID = 7, Copy on Write on page 0000003ffffff000
[S-MODE] PID = 7, Copy on Write on page 0000000000000000
[U] pid: 7 is running! global_variable: 2
[U] pid: 7 is running! global_variable: 3
[S-MODE] SET [PID = 8 PRIORITY = 2 COUNTER = 2]
[S-MODE] SET [PID = 7 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 6 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 5 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 4 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 3 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[S-MODE] switch to [PID = 8, COUNTER = 2, PRIORITY = 2]
[S-MODE] PID = 8, Copy on Write on page 0000003ffffff000
[S-MODE] PID = 8, Copy on Write on page 0000000000000000
[U] pid: 8 is running! global_variable: 2
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U] pid: 2 is running! global_variable: 5
[U] pid: 2 is running! global_variable: 6
[S-MODE] switch to [PID = 4, COUNTER = 4, PRIORITY = 4]
[U] pid: 4 is running! global_variable: 5
[U] pid: 4 is running! global_variable: 6
[S-MODE] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[U] pid: 3 is running! global_variable: 6
[U] pid: 3 is running! global_variable: 7
[S-MODE] switch to [PID = 5, COUNTER = 5, PRIORITY = 5]
[U] pid: 5 is running! global_variable: 4
[U] pid: 5 is running! global_variable: 5
[S-MODE] switch to [PID = 6, COUNTER = 5, PRIORITY = 5]
[U] pid: 6 is running! global_variable: 4
[U] pid: 6 is running! global_variable: 5
[S-MODE] switch to [PID = 7, COUNTER = 5, PRIORITY = 5]
[U] pid: 7 is running! global_variable: 4
[U] pid: 7 is running! global_variable: 5
[S-MODE] SET [PID = 8 PRIORITY = 2 COUNTER = 2]
[S-MODE] SET [PID = 7 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 6 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 5 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 4 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 3 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[S-MODE] switch to [PID = 8, COUNTER = 2, PRIORITY = 2]
[U] pid: 8 is running! global_variable: 3
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U] pid: 2 is running! global_variable: 7
[S-MODE] switch to [PID = 4, COUNTER = 4, PRIORITY = 4]
[U] pid: 4 is running! global_variable: 7
[S-MODE] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[U] pid: 3 is running! global_variable: 8
[S-MODE] switch to [PID = 5, COUNTER = 5, PRIORITY = 5]
[U] pid: 5 is running! global_variable: 6
[U] pid: 5 is running! global_variable: 7
[S-MODE] switch to [PID = 6, COUNTER = 5, PRIORITY = 5]
[U] pid: 6 is running! global_variable: 6
[U] pid: 6 is running! global_variable: 7
[S-MODE] switch to [PID = 7, COUNTER = 5, PRIORITY = 5]
[U] pid: 7 is running! global_variable: 6
[U] pid: 7 is running! global_variable: 7
```

## 思考题

1. 为什么我们在 [拷贝内核态进程状态](#拷贝内核态进程状态) 仅仅重新计算设置了 `sp` 与 `thread.sp`，但没有考虑同样发挥存储栈指针作用的 `thread.sscratch` 呢？那位于 `pt_regs` 中的 `sscratch` 又为什么没有被修改？
2. 在修改页表项的写权限时，我们需要使用 `sfence.vma` 指令来刷新 TLB。那如果我们不刷新 TLB，又可能会出现什么问题？
3. 对于提供的第 2 个 `main` 函数，在运行时，Message `Sys3-Lab7` 位于内存的什么位置？是否在读取的时候产生了 Page Fault？请给出必要的截图以说明。

## 作业提交

同学们需要提交实验报告以及整个工程代码。在提交前请使用 `make clean` 清除所有构建产物。

此外，在报告中需要给出 `getpid.c` 四个 `main` 函数各自的运行结果。如果不能全部实现，则可以只展示部分结果。

