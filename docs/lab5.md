<style>
code {
    font-family: ui-monospace, Cascadia, SFMono-Regular, Consolas, Menlo, monospace;
}
</style>

# 实验 5：RV64 缺页异常处理及 fork 机制

!!! info "25.04.23 发布、25.05.14 截止提交（三周）"

## 实验目的

- 通过 `vm_area_struct` 数据结构实现对进程**多区域**虚拟内存的管理。
- 在 [Lab4](lab4.md) 实现用户态程序的基础上，添加缺页异常处理 **page fault handler**。
- 为进程加入 **fork** 机制，能够支持通过 **fork** 创建新的用户态进程。

## 实验环境

- Debian 12 / Ubuntu 24.04 / ~~Ubuntu 22.04~~

## 背景知识

!!! tip ""

    下面是 Linux 中对于 VMA（Virtual Memory Area）和 page fault handler 的介绍（顺便帮大家复习下期末考）。由于 Linux 巨大的体量，无论是 VMA 还是 page fault 的逻辑都较为复杂，这里只要求大家实现简化版本的，所以不要在阅读背景介绍的时候有太大的压力。

### `vm_area_struct` 介绍

在 Linux 中，`vm_area_struct` 是虚拟内存管理的基本单元，保存了有关连续虚拟内存区域（简称 VMA）的信息。Linux 具体某一进程的虚拟内存区域映射关系可以通过 [procfs](https://man7.org/linux/man-pages/man5/procfs.5.html) 读取 `/proc/pid/maps` 的内容来获取:

比如，在一个常规的 shell 中，使用 `#!sh cat /proc/$$/maps`，可以查看当前 shell 具体的虚拟地址内存映射情况：

```console linenums="0"
/ # cat /proc/$$/maps
aaaaafc60000-aaaaafd32000 r-xp 00000000 00:5a 2300139                    /bin/busybox
aaaaafd4c000-aaaaafd50000 r--p 000dc000 00:5a 2300139                    /bin/busybox
aaaaafd50000-aaaaafd51000 rw-p 000e0000 00:5a 2300139                    /bin/busybox
aaaadb42c000-aaaadb42d000 ---p 00000000 00:00 0                          [heap]
aaaadb42d000-aaaadb42e000 rw-p 00000000 00:00 0                          [heap]
ffffa9392000-ffffa9434000 r-xp 00000000 00:5a 2300308                    /lib/ld-musl-aarch64.so.1
ffffa9437000-ffffa944d000 rw-p 00000000 00:00 0
ffffa944d000-ffffa944f000 r--p 00000000 00:00 0                          [vvar]
ffffa944f000-ffffa9451000 r-xp 00000000 00:00 0                          [vdso]
ffffa9451000-ffffa9452000 r--p 000af000 00:5a 2300308                    /lib/ld-musl-aarch64.so.1
ffffa9452000-ffffa9453000 rw-p 000b0000 00:5a 2300308                    /lib/ld-musl-aarch64.so.1
ffffa9453000-ffffa9455000 rw-p 00000000 00:00 0
ffffca36a000-ffffca38b000 rw-p 00000000 00:00 0                          [stack]
```

从中我们可以读取如下一些有关该进程内虚拟内存映射的关键信息：

- `vm_start`（第 1 列）：该段虚拟内存区域的开始地址
- `vm_end`（第 2 列）：该段虚拟内存区域的结束地址
- `vm_flags`（第 3 列）：该 `vm_area` 的一组权限（rwx）标志，`vm_flags` 的具体取值定义可参考 Linux 源代码的 [linux/mm.h](https://elixir.bootlin.com/linux/v5.15/source/include/linux/mm.h#L264-L429)
- `vm_pgoff`（第 4 列）：虚拟内存映射区域在文件内的偏移量
- `vm_file`（第 5/6/7 列）分别表示：映射文件所属设备号/指向关联文件结构的指针（如果有，一般为文件系统的 inode）/文件名

!!! note "关于虚拟内存区域"

    注意这里记录的 `vm_start` 和 `vm_end` 都是用户态的虚拟地址，并且内核并不会将除了用户程序会用到的内存区域以外的部分添加成为 VMA。

我们注意到，一段内存中的内容可能是映射到磁盘中的文件的。如果这样的内存的 VMA 产生了缺页异常，说明文件中对应的页不在操作系统的 buffer pool 中，或者是由于 buffer pool 的调度策略被换出到磁盘上了。这时候操作系统会用驱动读取硬盘上的内容，放入 buffer pool，然后修改当前进程的页表来让其能够用原来的地址访问文件内容。而这一切对用户程序来说是完全透明的，除了访问延迟。

除了映射到文件以外，VMA 还可能是一块匿名（anonymous）的区域。例如被标记为 `[stack]`、`[heap]` 的这些区域，并没有对应的文件。

其它保存在 `vm_area_struct` 中的信息还有：

- `vm_ops`：该 `vm_area` 中的一组工作函数
- `vm_next`/`vm_prev`：同一进程的所有虚拟内存区域由**链表结构**链接起来，这是分别指向前后两个 `vm_area_struct` 结构体的指针

可以发现，原本的 Linux 使用链表对一个进程内的 VMA 进行管理。但是由于如今一个程序可能体量非常巨大，所以现在的 Linux 已经用虚拟地址为索引来建立红黑树了。

### 缺页异常 Page Fault

在一个启用了虚拟内存的系统上，若正在运行的程序访问当前未由内存管理单元（MMU）映射到虚拟内存的页，或访问权限不足，则会由计算机硬件引发的缺页异常（page fault）。

处理缺页异常通常是操作系统内核的一部分。当处理缺页异常时，操作系统将尝试使所需页在物理内存中的位置变得可访问（建立新的映射关系到虚拟内存）。而如果在非法访问内存的情况下，发现触发 page fault 的虚拟内存地址（bad address）不在当前进程 `vm_area_struct` 链表所定义的允许访问的虚拟内存地址范围内，或访问位置的权限条件不满足时，缺页异常处理将终止该程序的继续运行。

#### Demand Paging

Demand paging 遵循的原则是，只有在执行进程需要时，才应将页放入内存中。这样做的好处是，仅加载执行进程所需的页，从而节省内存空间。例如，若一个页从未被访问过，那么它就不需要被放入内存中。

在 Lab4 的代码中，我们在 `task_init` 的时候创建了用户栈，并通过 `create_mapping` 在页表中创建了映射。在本次实验中，我们将修改为 demand paging 的方式，也就是在初始化 task 的时候不进行任何的映射（除了内核栈以及页表以外也不需要开辟其他空间），而是在发生缺页异常的时候检测到是记录在 VMA 中的合法地址后，再分配页并进行映射。

#### RISC-V Page Fault 及处理方式

在 RISC-V 中，当系统运行发生异常时，可通过解析 `scause` 寄存器的值，识别如下三种不同的 page fault：

| Interrupt | Exception Code | Description |
| :-: | :-: | --- |
| 0 | 12 | Instruction page fault |
| 0 | 13 | Load page fault |
| 0 | 15 | Store/AMO page fault |

处理缺页异常时可能所需的信息如下：

- 触发 page fault 时访问的虚拟内存地址。当触发 page fault 时，`stval` 寄存器由硬件设置为该出错的 VA 地址
- 导致 page fault 的类型，保存在 `scause` 寄存器中
- 发生 page fault 时的指令执行位置，保存在 `sepc` 中
- 当前进程合法的 VMA 映射关系，保存在 `vm_area_struct` 链表中
- 发生异常的虚拟地址对应的 PTE（page table entry）中记录的信息

总的说来，处理缺页异常需要进行以下步骤：

- 捕获异常
- 寻找当前 task 中导致产生了异常的地址对应的 VMA
    - 如果当前访问的虚拟地址在 VMA 中没有记录，即是不合法的地址，则运行出错（本实验不涉及）
    - 如果当前访问的虚拟地址在 VMA 中存在记录，则需要判断产生异常的原因：
        - 如果是匿名区域，那么开辟一页内存，然后把这一页映射到产生异常的 task 的页表中
        - 如果不是，则访问的页是存在数据的（如代码），需要从相应位置读取出内容，然后映射到页表中
- 返回到产生了该缺页异常的那条指令，并继续执行程序

### Fork

Fork 是 Linux 中的重要 syscall，它的作用是将进行了该 syscall 的进程完整地复制一份，并加入 ready queue。这样在下一次调度发生时，调度器就能够发现多了一个进程。从这时候开始，新的进程就可能被正式从 Ready 调度到 Running，而开始执行了。需留意，fork 具有以下特点：

- Fork 通过复制当前进程创建一个新的进程，新进程称为子进程，而原进程称为父进程。
- 子进程和父进程在不同的内存空间上运行。
- Fork 成功时，父进程返回子进程的 PID，子进程返回 0；失败时，父进程返回 -1。
- 创建的子进程需要深复制 `task_struct`，调整自己的页表、栈和 CSR 寄存器等信息，复制一份在用户态会用到的内存信息（用户态的栈、程序的代码和数据等），并且将自己伪装成是一个因为调度而加入了 ready queue 的普通程序来等待调度。在调度发生时，这个新进程就像是原本就在等待调度一样，被调度器选择并调度。
- Linux 中使用了 copy-on-write 机制，fork 创建的子进程首先与父进程共享物理内存空间，直到父子进程有修改内存的操作发生时再为子进程分配物理内存。本次实验中将实现一个简单的 COW 机制。

#### Fork 在 Linux 中的实际应用

Linux 的另一个重要 syscall 是 `execve`，它的作用是将进行了该 syscall 的进程换成另一个进程。这两个 syscall 一起，支撑起了 Linux 处理多任务的基础。当我们在 shell 里键入一个程序的目录时，shell（如 zsh 或 bash）会先进行一次 fork，这时候相当于有两个 shell 正在运行。然后其中的一个 shell 根据 fork 的返回值（是否为 0），发现自己和原本的 shell 不同，再调用 execve 来把自己给换成另一个程序，这样 shell 外的程序就得以执行了。

## 实验步骤

此次实验基于 [Lab4](lab4.md) 同学们所实现的代码进行。

### 准备工程

```text
└── user
    ├── src
    │   └── main.c
    └── uapp.lds
```

`src/lab5` 的目录结构如上。请同学们将以上文件同步到 `project/kernel` 对应目录下，**覆盖任何已有的文件**。

同学们需要完成以下工作：

- 按照如下修改 `user/Makefile`：

    ```diff title="(diff) user/Makefile" linenums="0"
    -CPPFLAGS += -I$(CURDIR)/include
    +U ?= PFH1
    +CPPFLAGS += -I$(CURDIR)/include -DUSER_MAIN=$(U)
    ```

!!! tip "关于 `user/src/main.c` 的说明"

    在 `user/src/main.c` 中我们定义了 6 个 `main` 函数，2 个用来测试 page fault handler，4 个用来测试 fork。

    - `make run` 默认运行 PFH1 也就是第一个 main 函数（和 lab4 的 getpid 一致）
    - `make run T=PFH2` 运行第二个 main 函数
    - `make run T=FORK1` 运行第三个 main 函数，检测单个 fork 与全局变量
    - `make run T=FORK2` 运行第四个 main 函数，检测单个 fork 与用户栈复制
    - `make run T=FORK3` 运行第五个 main 函数，检测多个 fork
    - `make run T=FORK4` 运行第六个 main 函数，检测单个 fork 计算斐波那契数列

    具体测试表现和预期见后文。同时 `main.c` 中我们通过 `delay` 函数等待一段时间，参数为 `DELAY_TIME` 宏定义，同学们可以自行修改这个数值来改变输出速度方便调试。为了加快实验表现，也可以修改时钟中断间隔。

### 缺页异常处理

#### 实现虚拟内存管理功能

每块 VMA 都有自己的 flag 来定义权限以及分类（是否匿名）。请修改 `proc.h`，在适当的位置加入/修改 VMA 相关的结构体定义：

```c title="arch/riscv/include/proc.h" linenums="0" hl_lines="50-51"
#define VM_READ 0x01
#define VM_WRITE 0x02
#define VM_EXEC 0x04
#define VM_ANON 0x08

struct vm_area_struct {
  /**
   * @brief The mm_struct we belong to.
   */
  struct mm_struct *vm_mm;

  /**
   * @brief Our start address within vm_mm.
   */
  void *vm_start;

  /**
   * @brief The past-the-end address within vm_mm.
   */
  void *vm_end;

  /**
   * @brief Flags as listed above.
   */
  unsigned vm_flags;

  /**
   * @brief linked list of VM areas per task, sorted by address.
   */
  struct vm_area_struct *vm_prev;
  struct vm_area_struct *vm_next;
};

struct mm_struct {
  /**
   * @brief list of VMAs.
   */
  struct vm_area_struct *mmap;
};

// 进程数据结构
struct task_struct {
  uint64_t pid;      // 进程 ID
  uint64_t state;    // 状态
  uint64_t priority; // 优先级
  uint64_t counter;  // 剩余时间

  struct thread_struct thread; // 线程结构

  pagetable_t pgd; // 页表

  struct mm_struct *mm;
};
```

!!! tip "注意 VMA 的 flags 和 PTE 的 flags 是不一样的，后面在实现的时候注意不要混淆两者。"

我们采用链表实现 VMA 的数据结构。对 VMA 链表的操作只需支持遍历和插入，并不复杂。

每一个 `vm_area_struct` 都对应于 task 地址空间的唯一**连续**区间。为了支持 demand paging，我们需要支持对 `vm_area_struct` 的添加和查找：

- `find_vma` 函数：实现对 `vm_area_struct` 的查找
    - 根据传入的地址 `addr`，遍历链表 `mm` 包含的 VMA 链表，找到该地址所在的 `vm_area_struct`
    - 如果链表中所有的 `vm_area_struct` 都不包含该地址，则返回 `NULL`
    ```c
    /**
     * @brief 遍历 mm，寻找 va 所在的 vm_area_struct
     *
     * @param mm 进程的 mm_struct
     * @param va 虚拟地址
     *
     * @return va 所在的 vm_area_struct 结构体指针，若未找到则返回 NULL
     */
    struct vm_area_struct *find_vma(struct mm_struct *mm, void *va);
    ```
    - 新建 `vm_area_struct` 结构体，根据传入的参数对结构体赋值，并添加到 `mm` 指向的 VMA 链表中
    ```c
    /**
     * @brief 向 mm 中添加一个 vm_area_struct
     *
     * @param mm 进程的 mm_struct
     * @param vm 要添加的 vm_area_struct 的起始地址
     * @param len vm_area_struct 记录的长度
     * @param flags vm_area_struct 的权限位
     *
     * @return 该映射的起始地址
     */
    ```

#### 修改 `task_init`

接下来我们要修改 `task_init` 来实现 demand paging。

Linux 在 page fault handler 中需要考虑多种情况。我们的实验经过简化，只需要根据 `vm_area_struct` 中的 `vm_flags` 来确定当前发生了什么样的错误，并且需要如何处理。在初始化一个 task 时我们既不分配内存，又不更改页表项来建立映射。回退到用户态进行程序执行的时候就会因为没有映射而发生 page fault，进入我们的 page fault handler 后，我们再分配空间（按需要复制内容）进行映射。

例如，我们原本要为用户态虚拟地址映射一个页，需要进行如下操作：

1. 调用 `alloc_page` 分配一页空间
2. 对这个页中的数据进行填充
3. 将这个页映射到用户空间，并设置好对应的 U、X、W、R、V 等 PTE 权限位，供用户程序访问
这个页时，会触发缺页异常。在缺页异常处理函数中，我们再根据缺页的地址，找到该地址对应的 VMA，根据 VMA 中的信息对页表进行映射。

所以我们需要修改 `task_init` 函数代码，更改为 demand paging：

- 删除（注释）之前实验中对 `uapp`、栈进行映射的代码
    - 代码和数据区域：该区域从虚拟地址 `USER_START` 开始，大小为 `#!c _euapp - _suapp`，权限与 Lab4 中 PTE 的权限一致；
    - 用户栈：范围为 `[USER_END - PGSIZE, USER_END)` ，权限在 Lab4 中 PTE 的基础上，还需增加 `VM_ANON` 表示该区域为匿名区域。

在完成上述修改之后，如果运行代码我们就可以截获一个 page fault：

```text linenums="0" hl_lines="2"
switch to [PID = 2, PRIORITY = 9, COUNTER = 9]
[S] Unhandled trap: scause = Instruction page fault (0xc), sepc = 0x0, stval = 0x0
```

可以看到，发生了缺页异常的 `sepc` 与 `stval` 是 `0x0`，说明我们在 `sret` 来执行用户态程序的时候，第一条指令就因为 PTE V bit 为 0 表征其映射的地址无效而发生了 instruction page fault。

#### 实现 Page Fault Handler

接下来我们需要修改 `trap.c`，为 `trap_handler` 添加捕获 page fault 的逻辑。

当捕获了 page fault 之后，需要实现缺页异常的处理函数 `do_page_fault`，它可以同时处理三种不同的 page fault。（哪三种？）

```c title="arch/riscv/kernel/trap.c" linenums="0"
static void do_page_fault(uint64_t scause, uint64_t stval) {
#error Not yet implemented
}
```

函数的具体逻辑为：

1. 通过 `stval` 获得访问出错的虚拟内存地址（bad address）；
2. 通过 `find_vma` 查找 bad address 是否在某个 VMA 中：
    1. 如果不在，说明 page fault 无法处理，则停止，可以输出相应的错误信息；
    2. 根据 VMA 的 flags 权限检查当前 page fault 的访问是否合法：
        1. 如果非法（比如触发了 Store/AMO page fault 但对应 VMA 不可写），则停止；
3. 到这里说明当前的 page fault 是合法的，接下来需要分配一页内存，并映射到对应的用户地址空间；
4. 通过 `#!c vma->vm_flags & VM_ANON` 获得当前的 VMA 是否是匿名空间：
    1. 如果是匿名空间，则直接映射即可；
    2. 如果不是，则需要根据 page fault 出错的地址，在 `.uapp` 段中读取对应的数据，将其复制到分配的内存中后做映射。

!!! tip "需要注意 bad address 并不一定是页对齐的，但在映射的时候 `pa` `va` 需要是页对齐的，要善用 `PGROUNDUP` 和 `PGROUNDDOWN` 宏。"

!!! tip "因为我们从 `task_init` 一次复制所有空间变成了一次只复制一页，所以同学们需要仔细区分需要填充页数据的情况，必要的时候画个图会有很大帮助。"

#### 测试缺页异常处理

至此，同学们已经完成了缺页异常处理的部分，可以使用 2 个 PFH 测试程序来测试自己的实现是否正确。样例输出如下，其中的额外输出可供参考：

??? success "`make run T=PFH1`"

    可以看到直到 `task_init` 完成，都只有 `setup_vm_final` 的时候创建了映射，用户态进程的拷贝和映射都在调度之后遇到 page fault 才触发，并且只有第一次触发了：

    ```text linenums="0" hl_lines="9-13 27 39 51 61-65 74 80 86 90-94"
    OpenSBI v1.5
        ...
    ...buddy_init done! size = 32768
    pgtbl = 0x8020c000: map [0xffffffe000200000, 0xffffffe000204000) -> [0x80200000, 0x80204000), perm = 0xa, size = 16384
    pgtbl = 0x8020c000: map [0xffffffe000204000, 0xffffffe000206000) -> [0x80204000, 0x80206000), perm = 0x2, size = 8192
    pgtbl = 0x8020c000: map [0xffffffe000206000, 0xffffffe008200000) -> [0x80206000, 0x88200000), perm = 0x6, size = 134193152
    ...task_init done!
    2025 ZJU Computer System III
    SET [PID = 1, PRIORITY = 5, COUNTER = 5]
    SET [PID = 2, PRIORITY = 9, COUNTER = 9]
    SET [PID = 3, PRIORITY = 3, COUNTER = 3]
    SET [PID = 4, PRIORITY = 5, COUNTER = 5]
    switch to [PID = 2, PRIORITY = 9, COUNTER = 9]
    [S] Instruction page fault; sepc = 0x0, stval = 0x0
    vma = 0xffffffe000320000, pgtbl = 0x8031a000: map [0, 0x1000) -> [0x80334000, 0x80335000), perm = 0xdf, size = 4096
    [S] Store/AMO page fault; sepc = 0x78, stval = 0x3ffffffff8
    vma = 0xffffffe000321000, pgtbl = 0x8031a000: map [0x3ffffff000, 0x4000000000) -> [0x80337000, 0x80338000), perm = 0xd7, size = 4096
    [S] Instruction page fault; sepc = 0x1808, stval = 0x1808
    vma = 0xffffffe000320000, pgtbl = 0x8031a000: map [0x1000, 0x2000) -> [0x8033a000, 0x8033b000), perm = 0xdf, size = 4096
    [U] [PID = 2, sp = 0x3ffffffff0]
    [U] [PID = 2, sp = 0x3ffffffff0]
    [U] [PID = 2, sp = 0x3ffffffff0]
    [U] [PID = 2, sp = 0x3ffffffff0]
    [U] [PID = 2, sp = 0x3ffffffff0]
    [U] [PID = 2, sp = 0x3ffffffff0]
    [U] [PID = 2, sp = 0x3ffffffff0]
    switch to [PID = 1, PRIORITY = 5, COUNTER = 5]
    [S] Instruction page fault; sepc = 0x0, stval = 0x0
    vma = 0xffffffe000313000, pgtbl = 0x80311000: map [0, 0x1000) -> [0x8033b000, 0x8033c000), perm = 0xdf, size = 4096
    [S] Store/AMO page fault; sepc = 0x78, stval = 0x3ffffffff8
    vma = 0xffffffe000318000, pgtbl = 0x80311000: map [0x3ffffff000, 0x4000000000) -> [0x8033e000, 0x8033f000), perm = 0xd7, size = 4096
    [S] Instruction page fault; sepc = 0x1808, stval = 0x1808
    vma = 0xffffffe000313000, pgtbl = 0x80311000: map [0x1000, 0x2000) -> [0x80341000, 0x80342000), perm = 0xdf, size = 4096
    [U] [PID = 1, sp = 0x3ffffffff0]
    [U] [PID = 1, sp = 0x3ffffffff0]
    [U] [PID = 1, sp = 0x3ffffffff0]
    [U] [PID = 1, sp = 0x3ffffffff0]
    [U] [PID = 1, sp = 0x3ffffffff0]
    switch to [PID = 4, PRIORITY = 5, COUNTER = 5]
    [S] Instruction page fault; sepc = 0x0, stval = 0x0
    vma = 0xffffffe00032e000, pgtbl = 0x8032c000: map [0, 0x1000) -> [0x80342000, 0x80343000), perm = 0xdf, size = 4096
    [S] Store/AMO page fault; sepc = 0x78, stval = 0x3ffffffff8
    vma = 0xffffffe00032f000, pgtbl = 0x8032c000: map [0x3ffffff000, 0x4000000000) -> [0x80345000, 0x80346000), perm = 0xd7, size = 4096
    [S] Instruction page fault; sepc = 0x1808, stval = 0x1808
    vma = 0xffffffe00032e000, pgtbl = 0x8032c000: map [0x1000, 0x2000) -> [0x80348000, 0x80349000), perm = 0xdf, size = 4096
    [U] [PID = 4, sp = 0x3ffffffff0]
    [U] [PID = 4, sp = 0x3ffffffff0]
    [U] [PID = 4, sp = 0x3ffffffff0]
    [U] [PID = 4, sp = 0x3ffffffff0]
    [U] [PID = 4, sp = 0x3ffffffff0]
    switch to [PID = 3, PRIORITY = 3, COUNTER = 3]
    [S] Instruction page fault; sepc = 0x0, stval = 0x0
    vma = 0xffffffe000329000, pgtbl = 0x80323000: map [0, 0x1000) -> [0x80349000, 0x8034a000), perm = 0xdf, size = 4096
    [S] Store/AMO page fault; sepc = 0x78, stval = 0x3ffffffff8
    vma = 0xffffffe00032a000, pgtbl = 0x80323000: map [0x3ffffff000, 0x4000000000) -> [0x8034c000, 0x8034d000), perm = 0xd7, size = 4096
    [S] Instruction page fault; sepc = 0x1808, stval = 0x1808
    vma = 0xffffffe000329000, pgtbl = 0x80323000: map [0x1000, 0x2000) -> [0x8034f000, 0x80350000), perm = 0xdf, size = 4096
    [U] [PID = 3, sp = 0x3ffffffff0]
    [U] [PID = 3, sp = 0x3ffffffff0]
    [U] [PID = 3, sp = 0x3ffffffff0]
    SET [PID = 1, PRIORITY = 5, COUNTER = 5]
    SET [PID = 2, PRIORITY = 9, COUNTER = 9]
    SET [PID = 3, PRIORITY = 3, COUNTER = 3]
    SET [PID = 4, PRIORITY = 5, COUNTER = 5]
    switch to [PID = 2, PRIORITY = 9, COUNTER = 9]
    [U] [PID = 2, sp = 0x3ffffffff0]
    [U] [PID = 2, sp = 0x3ffffffff0]
    [U] [PID = 2, sp = 0x3ffffffff0]
    [U] [PID = 2, sp = 0x3ffffffff0]
    [U] [PID = 2, sp = 0x3ffffffff0]
    [U] [PID = 2, sp = 0x3ffffffff0]
    [U] [PID = 2, sp = 0x3ffffffff0]
    [U] [PID = 2, sp = 0x3ffffffff0]
    switch to [PID = 1, PRIORITY = 5, COUNTER = 5]
    [U] [PID = 1, sp = 0x3ffffffff0]
    [U] [PID = 1, sp = 0x3ffffffff0]
    [U] [PID = 1, sp = 0x3ffffffff0]
    [U] [PID = 1, sp = 0x3ffffffff0]
    [U] [PID = 1, sp = 0x3ffffffff0]
    switch to [PID = 4, PRIORITY = 5, COUNTER = 5]
    [U] [PID = 4, sp = 0x3ffffffff0]
    [U] [PID = 4, sp = 0x3ffffffff0]
    [U] [PID = 4, sp = 0x3ffffffff0]
    [U] [PID = 4, sp = 0x3ffffffff0]
    [U] [PID = 4, sp = 0x3ffffffff0]
    switch to [PID = 3, PRIORITY = 3, COUNTER = 3]
    [U] [PID = 3, sp = 0x3ffffffff0]
    [U] [PID = 3, sp = 0x3ffffffff0]
    [U] [PID = 3, sp = 0x3ffffffff0]
    SET [PID = 1, PRIORITY = 5, COUNTER = 5]
    SET [PID = 2, PRIORITY = 9, COUNTER = 9]
    SET [PID = 3, PRIORITY = 3, COUNTER = 3]
    SET [PID = 4, PRIORITY = 5, COUNTER = 5]
    switch to [PID = 2, PRIORITY = 9, COUNTER = 9]
    ```

!!! success "`make run T=PFH2`"

    PFH2 的输出内容较多，此处我们不放出完整的输出。同学们参考 PFH2 的测试代码对照输出即可。程序应该在输出 4096 个字符后，在 4 KiB 对齐的地址发生 Store/AMO page fault，之后继续输出 4096 个字符，如此循环。

!!! note "与之前的实验相同，输出只要能表现 kernel 行为正确即可，具体每个 task 输出行数和内容都不重要"

### 实现 fork 机制

#### 框架代码导读与修改

在 `user/src/main.c` 中有 4 个 fork 测试函数，同学们可以通过启用不同的 `main` 函数来测试阶段性功能是否正确实现。

`mm.h` 提供了用于对页引用计数的接口，方便同学们实现 fork 时的 COW 机制。其逻辑并不复杂，同学们可以参考 `mm.c` 中的实现进行理解。其中 `ref_cnt` 用于记录页的引用计数，`buddy_pfn_incref` 和 `buddy_pfn_decref` 函数分别用于增加和减少页的引用计数。理解引用计数的部分并不需要深入 buddy 系统的细节，同学们在阅读代码时不用有很大压力。

```c title="arch/riscv/include/mm.h" linenums="40"
/**
 * @brief 增加页表引用计数
 *
 * @param va 要增加引用计数的物理内存的虚拟地址
 * @return 若 va 是无效的，则返回 -1；否则返回 0
 */
int ref_page(void *va);

/**
 * @brief 减少页表引用计数
 *
 * 当引用计数为 0 时，释放物理内存
 *
 * @param va 要减少引用计数的物理内存的虚拟地址
 * @return 若 va 是无效的，则返回 -1；否则返回 0
 */
int deref_page(void *va);
```

在 [Lab3](lab3.md) 中，我们曾经提及 RISC-V Sv39 模式的页表项：

!!! quote "§10.4.1. Addressing and Memory Protection (Sv39)"

    ```text linenums="0"
    63 62  61 60      54 53       28 27        19 18        10 9   8 7 6 5 4 3 2 1 0
    ┌─┬──────┬──────────┬───────────┬────────────┬────────────┬─────┬─┬─┬─┬─┬─┬─┬─┬─┐
    │N| PBMT | Reserved |  PPN[2]   │   PPN[1]   │   PPN[0]   │ RSW │D│A│G│U│X│W│R│V│
    └─┴──────┴──────────┴───────────┴────────────┴────────────┴─────┴─┴─┴─┴─┴─┴─┴─┴─┘
                         Reserved for use by supervisor software ┘   │ │ │ │ │ │ │ │
                                                       (*) Dirty ────┘ │ │ │ │ │ │ │
                                                    (*) Accessed ──────┘ │ │ │ │ │ │
                                                          Global ────────┘ │ │ │ │ │
                                                            User ──────────┘ │ │ │ │
                                                      Executable ────────────┘ │ │ │
                                                        Writable ──────────────┘ │ │
                                                        Readable ────────────────┘ │
                                                           Valid ──────────────────┘
    ```

在本次实验中，我们可以使用 RSW 其中一位来标记页是否为共享页。例如，我们可以在 `vm.h` 中添加如下的定义：

```c title="arch/riscv/include/vm.h" linenums="0"
#define PTE_S 0x100
```

!!! tip "为了方便实验中深复制页表，推荐同学们实现 `walk_page_table` 函数，用于遍历页表，找到 VA 对应的 PA/PTE。"

#### 表面的准备工作

在实现较为复杂的 fork 流程之前，我们先将框架搭好，具体要做的有以下两件事：

- 修改 proc 相关代码，使其只初始化一个进程，其他进程保留为 NULL 等待 fork 创建；

    !!! tip "如何实现？"

        注意到我们目前只需要考虑添加进程而不需要考虑删除进程，所以我们需要一个新的变量记录当前进程的数量，以及将之前 kernel 中所有用到 `NR_TASKS` 的地方都改为使用这个新的变量。

        `NR_TASKS` 现在表示的是最大进程数，我们需要增加其值。为了完成 FORK3 测试，它至少需要为 1+8。

    !!! warning "在运行 PFH 测试和 FORK 测试时这里的行为是不一样的，PFH 测试仍然需要初始化所有进程，而 FORK 测试只需要初始化一个进程。"

- 添加系统调用处理。

    !!! tip "如何实现？"
        Fork 在 RISC-V Linux 中的系统调用是 `sys_clone`，syscall 号为 220，所以需要在 `include/syscalls.h` 中添加 `__NR_clone` 的定义。

        ```c title="include/syscalls.h" linenums="0"
        #define __NR_clone 220
        ```

        ```c title="arch/riscv/include/ksyscalls.h" linenums="0"
        struct pt_regs;
        long sys_clone(struct pt_regs *regs);
        ```

        需要注意，Linux 的 clone 系统调用远比我们实验中的 fork 复杂得多，涉及到线程、信号等多种功能。为简化实现，我们只需要实现最基本的 fork 功能即可，参数也只需要传递 `#!c struct pt_regs`，你可以按照自己的实现添加其他参数。

        然后在 syscall 的处理函数中，检测到 `#!c regs->a7 == __NR_clone` 时，调用 `sys_clone` 函数来完成 fork 的工作。

        ```c title="arch/riscv/kernel/ksyscalls.c" linenums="0"
        long sys_clone(struct pt_regs *regs) {
          long do_fork(struct pt_regs *regs);
          return do_fork(regs);
        }
        ```

        `do_fork` 就是我们最终要实现的 fork 处理函数。

        ```c
        long do_fork(struct pt_regs *regs);
        ```

#### 复制内核态进程状态

我们先前提及，`fork` 的目标是父进程完整地复制一份，从而得到一个子进程。牢记这个目标，那么我们需要考虑的复制内容就很显然了，都在 `#!c struct task_struct` 中：

```c
struct task_struct {
  uint64_t pid;      // 进程 ID
  uint64_t state;    // 状态
  uint64_t priority; // 优先级
  uint64_t counter;  // 剩余时间

  struct thread_struct thread; // 线程结构

  pagetable_t pgd; // 页表

  struct mm_struct *mm;
};
```

我们采用自顶向下的思想，先来处理内核态的状态。

回忆一下我们是怎样使用 `task_struct` 的，我们并不是分配了一块刚好大小的空间，而是分配了一整个页，并将页的高处作为了 task 的内核态栈：

``` linenums="0"
                ┌─────────────┐◄─── High address
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
  4 KiB Page    │             │
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

这意味着，内核态的所有数据、状态都包含在了这一页中，很大程度上简化了我们的实验。同学们只需要深复制一份这页的内容，并修改一些与新进程相关的内容即可；至于页表和内存管理的内容，我们会在后面的步骤中处理。**一些**需要提醒的修改内容如下：

- 选择一个空闲的 PID 作为子进程的 PID，将其放置到 `task` 数组中
- `counter` 设置为 0 即可，等待调度函数重新分配
- 当子进程被调度时，`__switch_to` 会从子进程的 `thread_struct` 等成员变量中加载在 `do_fork` 中写入的值，因此需要正确设置 `thread_struct` 结构体的内容：
    - 设置 `#!c thread.ra` 为 `ret_from_fork`（详见[设置子进程返回逻辑](#_14)）
    - 设置 `#!c thread.sp` 为子进程的内核栈 `sp`（可以根据父进程 `task_struct` 地址、父进程 `sp` 与子进程 `task_struct` 地址计算得到）
- 在 `ret_from_fork` 中，我们将会根据内核栈中保存的 `#!c struct pt_regs` 中对寄存器状态进行恢复。同学们可以考虑子进程的返回值 `a0`、栈指针、返回地址等内容。

#### 复制用户态进程状态

抽丝剥茧，我们现在剩下的主要任务就是处理子进程在用户态下的页表和内存管理了。

先从比较简单的内存管理开始。我们知道子进程的内存管理结构 `mm` 既需要和父进程一致，又不能影响父进程，因此我们需要**深复制**一份父进程的 `mm`。请注意，这是一个**链表**，同学们需要正确地处理链表的深复制。

接着，让我们处理页表的复制。为了能在内核态正确运行，分配一个页给用户根页表 `pgd` 后，复制内核根页表 `swapper_pg_dir` 必不可少。接下来，我们需要让用户态程序能够正确的找到虚拟地址对应的物理地址。如果我们不需要实现 COW 机制，那么我们只需要通过遍历 `mm` 中保存的 VMA，将每个已经在父进程中映射的页在子进程中复制并映射即可；而为了实现 COW 机制，在此处，只需要将复制的过程修改为：使用 `ref_page` 函数增加页引用计数，然后清除页表项的 W 位，设置 S 位（如上定义的 `PTE_S`）置位。当然，别忘了在这之后对子进程的页表进行映射。

!!! warning "刷新 TLB"

    在前面的过程中，我们更改了页表项的权限。在这之后，一个刷新 TLB 的操作是不可缺少的（`#!asm sfence.vma`）。

#### 设置父进程返回值

在 `do_fork` 中，我们需要设置父进程的返回值，即子进程的 PID。

至此，`do_fork` 的实现就完成了，父进程应该可以使用 `fork` 获得子进程的 PID 了。不过，子进程尚且不能运行，其返回逻辑还需要我们稍加处理。

#### 设置子进程返回逻辑

在实际动手之前，让我们先考虑一下父进程与子进程二者的返回路径。对于父进程而言，该路径为 `do_fork` -> `sys_clone` -> `trap_handler` -> `_traps` -> $sepc；而通过上面的实现，我们知道，子进程的返回路径为 `__switch_to` -> `ret_from_fork` -> `...` -> $sepc。那么很显然，`ret_from_fork` 与 `_traps` 有着很密切的关系。再仔细想想，子进程既然是父进程状态的复制，那么对于子进程而言，它是不是也像父进程从 `trap_handler` 中返回一样，认为自己是刚执行完一个 syscall 呢？

这样的话，需要进行的工作就比较显然了。利用 `__switch_to` 时恢复的 `ra` 与 `sp`，我们可以实现一个类似于 ROP (return oriented programming) 的操作，跳转到 `_traps` 中从 `trap_handler` 返回的位置：

```asm
    ...
    jal ra, trap_handler

    .globl ret_from_fork
ret_from_fork:
    # restore...
```

这样，子进程就可以像父进程一样，从 `trap_handler` 返回，继续执行用户程序了。

#### 添加新的 Page Fault 处理

还记得我们删除了页表项的写权限吗？这意味着，当父子线程中有一个线程试图写入一个共享页时，会触发一个 Store/AMO page fault。我们需要在 `do_page_fault` 中添加对这种情况的处理。当发生这种情况时，我们需要为该进程分配一个新的页，将原页的内容复制到新页中，并将新页进行映射。

!!! tip "关于引用计数"

    对于原先的页，别忘了使用 `deref_page` 减少页引用计数。这样父子进程想要写入的时候，都会触发 COW，并复制一个新页。当一个页的引用计数降为 0 时，会由 buddy system 自动释放。

    进一步的，父进程 COW 后，子进程再进行写入的时候，也可以在这时判断引用计数，如果计数为 1，说明这个页只有一个引用，那么就可以直接去掉 S 位，添加 W 位，这样可以免去一次额外的复制。

#### 测试 fork

至此，正确实现的话就可以正常运行全部的测试了，接下来给出 4 个用于 fork 的测试的示例输出和测试目的。对于 fork 测试函数，需要同学们在 COW 发生时打印一些信息，以便检查 COW 是否正确实现。

??? success "`make run T=FORK1`"

    注意到 PID 1 在 fork 出 PID 2 时将现有的 `create_mapping` 的 2 个页复制并映射到 PID 2 的页表中，在调度后 PID 2 开始运行，且全局变量 `var` 的值相互独立。后续 page fault 也是为各自的页表添加映射。

    ```text linenums="0" hl_lines="9-10 15 22-23 27-33 36-37 41-56"
    OpenSBI v1.5
        ...
    ...buddy_init done! size = 32768
    pgtbl = 0x8020c000: map [0xffffffe000200000, 0xffffffe000204000) -> [0x80200000, 0x80204000), perm = 0xa, size = 16384
    pgtbl = 0x8020c000: map [0xffffffe000204000, 0xffffffe000206000) -> [0x80204000, 0x80206000), perm = 0x2, size = 8192
    pgtbl = 0x8020c000: map [0xffffffe000206000, 0xffffffe008200000) -> [0x80206000, 0x88200000), perm = 0x6, size = 134193152
    ...task_init done!
    2025 ZJU Computer System III
    SET [PID = 1, PRIORITY = 5, COUNTER = 5]
    switch to [PID = 1, PRIORITY = 5, COUNTER = 5]
    [S] Instruction page fault; sepc = 0x0, stval = 0x0
    vma = 0xffffffe000313000, pgtbl = 0x80311000: map [0, 0x1000) -> [0x80319000, 0x8031a000), perm = 0xdf, size = 4096
    [S] Store/AMO page fault; sepc = 0x78, stval = 0x3ffffffff8
    vma = 0xffffffe000318000, pgtbl = 0x80311000: map [0x3ffffff000, 0x4000000000) -> [0x8031c000, 0x8031d000), perm = 0xd7, size = 4096
    do_fork: 1 -> 2
    pgtbl = 0x80311000: map [0, 0x1000) -> [0x80319000, 0x8031a000), perm = 0x1db, size = 4096
    pgtbl = 0x80321000: map [0, 0x1000) -> [0x80319000, 0x8031a000), perm = 0x1db, size = 4096
    pgtbl = 0x80311000: map [0x3ffffff000, 0x4000000000) -> [0x8031c000, 0x8031d000), perm = 0x1d3, size = 4096
    pgtbl = 0x80321000: map [0x3ffffff000, 0x4000000000) -> [0x8031c000, 0x8031d000), perm = 0x1d3, size = 4096
    [S] Load page fault; sepc = 0xa0, stval = 0x2370
    vma = 0xffffffe000313000, pgtbl = 0x80311000: map [0x2000, 0x3000) -> [0x80328000, 0x80329000), perm = 0xdf, size = 4096
    [S] Store/AMO page fault; sepc = 0x124, stval = 0x3fffffffa8
    vma = 0xffffffe000318000, SHARED PAGE [PID = 1], copy 0x8031c000 to 0x80329000
    pgtbl = 0x80311000: map [0x3ffffff000, 0x4000000000) -> [0x80329000, 0x8032a000), perm = 0xd7, size = 4096
    [S] Instruction page fault; sepc = 0x185c, stval = 0x185c
    vma = 0xffffffe000313000, pgtbl = 0x80311000: map [0x1000, 0x2000) -> [0x8032a000, 0x8032b000), perm = 0xdf, size = 4096
    [U-PARN] [PID = 1] var = 0
    [U-PARN] [PID = 1] var = 1
    [U-PARN] [PID = 1] var = 2
    [U-PARN] [PID = 1] var = 3
    SET [PID = 1, PRIORITY = 5, COUNTER = 5]
    SET [PID = 2, PRIORITY = 9, COUNTER = 9]
    switch to [PID = 2, PRIORITY = 9, COUNTER = 9]
    [S] Load page fault; sepc = 0xa0, stval = 0x2370
    vma = 0xffffffe000322000, pgtbl = 0x80321000: map [0x2000, 0x3000) -> [0x8032b000, 0x8032c000), perm = 0xdf, size = 4096
    [S] Store/AMO page fault; sepc = 0x124, stval = 0x3fffffffa8
    vma = 0xffffffe000325000, SHARED PAGE [PID = 2], copy 0x8031c000 to 0x8032c000
    pgtbl = 0x80321000: map [0x3ffffff000, 0x4000000000) -> [0x8032c000, 0x8032d000), perm = 0xd7, size = 4096
    [S] Instruction page fault; sepc = 0x185c, stval = 0x185c
    vma = 0xffffffe000322000, pgtbl = 0x80321000: map [0x1000, 0x2000) -> [0x8031c000, 0x8031d000), perm = 0xdf, size = 4096
    [U-CHLD] [PID = 2] var = 0
    [U-CHLD] [PID = 2] var = 1
    [U-CHLD] [PID = 2] var = 2
    [U-CHLD] [PID = 2] var = 3
    [U-CHLD] [PID = 2] var = 4
    [U-CHLD] [PID = 2] var = 5
    [U-CHLD] [PID = 2] var = 6
    [U-CHLD] [PID = 2] var = 7
    switch to [PID = 1, PRIORITY = 5, COUNTER = 5]
    [U-PARN] [PID = 1] var = 4
    [U-PARN] [PID = 1] var = 5
    [U-PARN] [PID = 1] var = 6
    [U-PARN] [PID = 1] var = 7
    SET [PID = 1, PRIORITY = 5, COUNTER = 5]
    SET [PID = 2, PRIORITY = 9, COUNTER = 9]
    switch to [PID = 2, PRIORITY = 9, COUNTER = 9]
    ```

??? success "`make run T=FORK2`"

    本测试的主要输出现象为，父进程在给 `var` 自增了 3 次，为 `space` 中复制了字符串之后才 fork 出子进程，子进程应该要通过深拷贝页表来保留这些信息。PID 2 开始运行时也应该正确输出 ZJU Sys3 Lab5 字符串，并且 `var` 从 3 开始自增，且后续和父进程互不影响。

    ```text linenums="0" hl_lines="10 24 35-36 38-40 45-47 49-51"
    OpenSBI v1.5
        ...
    ...buddy_init done! size = 32768
    pgtbl = 0x8020c000: map [0xffffffe000200000, 0xffffffe000204000) -> [0x80200000, 0x80204000), perm = 0xa, size = 16384
    pgtbl = 0x8020c000: map [0xffffffe000204000, 0xffffffe000206000) -> [0x80204000, 0x80206000), perm = 0x2, size = 8192
    pgtbl = 0x8020c000: map [0xffffffe000206000, 0xffffffe008200000) -> [0x80206000, 0x88200000), perm = 0x6, size = 134193152
    ...task_init done!
    2025 ZJU Computer System III
    SET [PID = 1, PRIORITY = 5, COUNTER = 5]
    switch to [PID = 1, PRIORITY = 5, COUNTER = 5]
    [S] Instruction page fault; sepc = 0x0, stval = 0x0
    vma = 0xffffffe000315000, pgtbl = 0x80313000: map [0, 0x1000) -> [0x80317000, 0x80318000), perm = 0xdf, size = 4096
    [S] Store/AMO page fault; sepc = 0x78, stval = 0x3ffffffff8
    vma = 0xffffffe000316000, pgtbl = 0x80313000: map [0x3ffffff000, 0x4000000000) -> [0x80322000, 0x80323000), perm = 0xd7, size = 4096
    [S] Load page fault; sepc = 0x98, stval = 0x2458
    vma = 0xffffffe000315000, pgtbl = 0x80313000: map [0x2000, 0x3000) -> [0x80325000, 0x80326000), perm = 0xdf, size = 4096
    [S] Instruction page fault; sepc = 0x18d8, stval = 0x18d8
    vma = 0xffffffe000315000, pgtbl = 0x80313000: map [0x1000, 0x2000) -> [0x80326000, 0x80327000), perm = 0xdf, size = 4096
    [U] [PID = 1] var = 0
    [U] [PID = 1] var = 1
    [U] [PID = 1] var = 2
    [S] Store/AMO page fault; sepc = 0x4a8, stval = 0x3468
    vma = 0xffffffe000315000, pgtbl = 0x80313000: map [0x3000, 0x4000) -> [0x80327000, 0x80328000), perm = 0xdf, size = 4096
    do_fork: 1 -> 2
    pgtbl = 0x80313000: map [0, 0x1000) -> [0x80317000, 0x80318000), perm = 0x1db, size = 4096
    pgtbl = 0x8032a000: map [0, 0x1000) -> [0x80317000, 0x80318000), perm = 0x1db, size = 4096
    pgtbl = 0x80313000: map [0x1000, 0x2000) -> [0x80326000, 0x80327000), perm = 0x1db, size = 4096
    pgtbl = 0x8032a000: map [0x1000, 0x2000) -> [0x80326000, 0x80327000), perm = 0x1db, size = 4096
    pgtbl = 0x80313000: map [0x2000, 0x3000) -> [0x80325000, 0x80326000), perm = 0x1db, size = 4096
    pgtbl = 0x8032a000: map [0x2000, 0x3000) -> [0x80325000, 0x80326000), perm = 0x1db, size = 4096
    pgtbl = 0x80313000: map [0x3000, 0x4000) -> [0x80327000, 0x80328000), perm = 0x1db, size = 4096
    pgtbl = 0x8032a000: map [0x3000, 0x4000) -> [0x80327000, 0x80328000), perm = 0x1db, size = 4096
    pgtbl = 0x80313000: map [0x3ffffff000, 0x4000000000) -> [0x80322000, 0x80323000), perm = 0x1d3, size = 4096
    pgtbl = 0x8032a000: map [0x3ffffff000, 0x4000000000) -> [0x80322000, 0x80323000), perm = 0x1d3, size = 4096
    [S] Store/AMO page fault; sepc = 0x1a0, stval = 0x3fffffffa8
    vma = 0xffffffe000316000, SHARED PAGE [PID = 1], copy 0x80322000 to 0x80331000
    pgtbl = 0x80313000: map [0x3ffffff000, 0x4000000000) -> [0x80331000, 0x80332000), perm = 0xd7, size = 4096
    [U-PARN] [PID = 1] Message: ZJU Sys3 Lab5
    [S] Store/AMO page fault; sepc = 0x124, stval = 0x2458
    vma = 0xffffffe000315000, SHARED PAGE [PID = 1], copy 0x80325000 to 0x80332000
    pgtbl = 0x80313000: map [0x2000, 0x3000) -> [0x80332000, 0x80333000), perm = 0xdf, size = 4096
    [U-PARN] [PID = 1] var = 3
    SET [PID = 1, PRIORITY = 5, COUNTER = 5]
    SET [PID = 2, PRIORITY = 9, COUNTER = 9]
    switch to [PID = 2, PRIORITY = 9, COUNTER = 9]
    [S] Store/AMO page fault; sepc = 0x1a0, stval = 0x3fffffffa8
    vma = 0xffffffe00032e000, SHARED PAGE [PID = 2], copy 0x80322000 to 0x80333000
    pgtbl = 0x8032a000: map [0x3ffffff000, 0x4000000000) -> [0x80333000, 0x80334000), perm = 0xd7, size = 4096
    [U-CHLD] [PID = 2] Message: ZJU Sys3 Lab5
    [S] Store/AMO page fault; sepc = 0x124, stval = 0x2458
    vma = 0xffffffe00032b000, SHARED PAGE [PID = 2], copy 0x80325000 to 0x80322000
    pgtbl = 0x8032a000: map [0x2000, 0x3000) -> [0x80322000, 0x80323000), perm = 0xdf, size = 4096
    [U-CHLD] [PID = 2] var = 3
    [U-CHLD] [PID = 2] var = 4
    [U-CHLD] [PID = 2] var = 5
    [U-CHLD] [PID = 2] var = 6
    [U-CHLD] [PID = 2] var = 7
    [U-CHLD] [PID = 2] var = 8
    [U-CHLD] [PID = 2] var = 9
    [U-CHLD] [PID = 2] var = 10
    switch to [PID = 1, PRIORITY = 5, COUNTER = 5]
    [U-PARN] [PID = 1] var = 4
    [U-PARN] [PID = 1] var = 5
    [U-PARN] [PID = 1] var = 6
    [U-PARN] [PID = 1] var = 7
    [U-PARN] [PID = 1] var = 8
    SET [PID = 1, PRIORITY = 5, COUNTER = 5]
    SET [PID = 2, PRIORITY = 9, COUNTER = 9]
    switch to [PID = 2, PRIORITY = 9, COUNTER = 9]
    ```

!!! question "`make run T=FORK3`"

    FORK3 的代码中有 3 次 `fork` 调用，预期输出并不在这里呈现，需要你自己通过分析代码的预期结果来判断输出是否正确。同一个程序里多个 `fork` 也是在考试中较常见的题目，希望同学们可以通过本次实验以及分析这个测试更好掌握 fork 的原理。

??? success "`make run T=FORK4`"

    这个测试通过计算斐波那契数列来测试 fork 是否正确隔离了父子进程的内存空间。注意到 PID 1 和 PID 2 的斐波那契数列是相互独立的。同学们应该确保得到的结果和下方展示的类似。

    ```text linenums="1" hl_lines="10 21 32-33 37-39 78-79 83-85"
    OpenSBI v1.5
        ...
    ...buddy_init done! size = 32768
    pgtbl = 0x8020c000: map [0xffffffe000200000, 0xffffffe000204000) -> [0x80200000, 0x80204000), perm = 0xa, size = 16384
    pgtbl = 0x8020c000: map [0xffffffe000204000, 0xffffffe000206000) -> [0x80204000, 0x80206000), perm = 0x2, size = 8192
    pgtbl = 0x8020c000: map [0xffffffe000206000, 0xffffffe008200000) -> [0x80206000, 0x88200000), perm = 0x6, size = 134193152
    ...task_init done!
    2025 ZJU Computer System III
    SET [PID = 1, PRIORITY = 5, COUNTER = 5]
    switch to [PID = 1, PRIORITY = 5, COUNTER = 5]
    [S] Instruction page fault; sepc = 0x0, stval = 0x0
    vma = 0xffffffe000315000, pgtbl = 0x80313000: map [0, 0x1000) -> [0x80317000, 0x80318000), perm = 0xdf, size = 4096
    [S] Store/AMO page fault; sepc = 0x168, stval = 0x3ffffffff8
    vma = 0xffffffe000316000, pgtbl = 0x80313000: map [0x3ffffff000, 0x4000000000) -> [0x80322000, 0x80323000), perm = 0xd7, size = 4096
    [S] Store/AMO page fault; sepc = 0x1ac, stval = 0x2610
    vma = 0xffffffe000315000, pgtbl = 0x80313000: map [0x2000, 0x3000) -> [0x80325000, 0x80326000), perm = 0xdf, size = 4096
    [S] Store/AMO page fault; sepc = 0x1ac, stval = 0x3000
    vma = 0xffffffe000315000, pgtbl = 0x80313000: map [0x3000, 0x4000) -> [0x80326000, 0x80327000), perm = 0xdf, size = 4096
    [S] Store/AMO page fault; sepc = 0x1ac, stval = 0x4000
    vma = 0xffffffe000315000, pgtbl = 0x80313000: map [0x4000, 0x5000) -> [0x80327000, 0x80328000), perm = 0xdf, size = 4096
    do_fork: 1 -> 2
    pgtbl = 0x80313000: map [0, 0x1000) -> [0x80317000, 0x80318000), perm = 0x1db, size = 4096
    pgtbl = 0x8032a000: map [0, 0x1000) -> [0x80317000, 0x80318000), perm = 0x1db, size = 4096
    pgtbl = 0x80313000: map [0x2000, 0x3000) -> [0x80325000, 0x80326000), perm = 0x1db, size = 4096
    pgtbl = 0x8032a000: map [0x2000, 0x3000) -> [0x80325000, 0x80326000), perm = 0x1db, size = 4096
    pgtbl = 0x80313000: map [0x3000, 0x4000) -> [0x80326000, 0x80327000), perm = 0x1db, size = 4096
    pgtbl = 0x8032a000: map [0x3000, 0x4000) -> [0x80326000, 0x80327000), perm = 0x1db, size = 4096
    pgtbl = 0x80313000: map [0x4000, 0x5000) -> [0x80327000, 0x80328000), perm = 0x1db, size = 4096
    pgtbl = 0x8032a000: map [0x4000, 0x5000) -> [0x80327000, 0x80328000), perm = 0x1db, size = 4096
    pgtbl = 0x80313000: map [0x3ffffff000, 0x4000000000) -> [0x80322000, 0x80323000), perm = 0x1d3, size = 4096
    pgtbl = 0x8032a000: map [0x3ffffff000, 0x4000000000) -> [0x80322000, 0x80323000), perm = 0x1d3, size = 4096
    [S] Store/AMO page fault; sepc = 0x2d8, stval = 0x3fffffff68
    vma = 0xffffffe000316000, SHARED PAGE [PID = 1], copy 0x80322000 to 0x80331000
    pgtbl = 0x80313000: map [0x3ffffff000, 0x4000000000) -> [0x80331000, 0x80332000), perm = 0xd7, size = 4096
    [S] Instruction page fault; sepc = 0x1a10, stval = 0x1a10
    vma = 0xffffffe000315000, pgtbl = 0x80313000: map [0x1000, 0x2000) -> [0x80332000, 0x80333000), perm = 0xdf, size = 4096
    [U] fork returns 2
    [S] Store/AMO page fault; sepc = 0x1e0, stval = 0x2600
    vma = 0xffffffe000315000, SHARED PAGE [PID = 1], copy 0x80325000 to 0x80333000
    pgtbl = 0x80313000: map [0x2000, 0x3000) -> [0x80333000, 0x80334000), perm = 0xdf, size = 4096
    [U-PARN] [PID = 1] the 0th fibonacci number is 1 and the 999th number in the big array is 2998
    [U-PARN] [PID = 1] the 1st fibonacci number is 1 and the 998th number in the big array is 2995
    [U-PARN] [PID = 1] the 2nd fibonacci number is 1 and the 997th number in the big array is 2992
    [U-PARN] [PID = 1] the 3rd fibonacci number is 2 and the 996th number in the big array is 2989
    [U-PARN] [PID = 1] the 4th fibonacci number is 3 and the 995th number in the big array is 2986
    [U-PARN] [PID = 1] the 5th fibonacci number is 5 and the 994th number in the big array is 2983
    [U-PARN] [PID = 1] the 6th fibonacci number is 8 and the 993rd number in the big array is 2980
    [U-PARN] [PID = 1] the 7th fibonacci number is 13 and the 992nd number in the big array is 2977
    [U-PARN] [PID = 1] the 8th fibonacci number is 21 and the 991st number in the big array is 2974
    [U-PARN] [PID = 1] the 9th fibonacci number is 34 and the 990th number in the big array is 2971
    [U-PARN] [PID = 1] the 10th fibonacci number is 55 and the 989th number in the big array is 2968
    [U-PARN] [PID = 1] the 11th fibonacci number is 89 and the 988th number in the big array is 2965
    [U-PARN] [PID = 1] the 12th fibonacci number is 144 and the 987th number in the big array is 2962
    [U-PARN] [PID = 1] the 13th fibonacci number is 233 and the 986th number in the big array is 2959
    [U-PARN] [PID = 1] the 14th fibonacci number is 377 and the 985th number in the big array is 2956
    [U-PARN] [PID = 1] the 15th fibonacci number is 610 and the 984th number in the big array is 2953
    [U-PARN] [PID = 1] the 16th fibonacci number is 987 and the 983rd number in the big array is 2950
    [U-PARN] [PID = 1] the 17th fibonacci number is 1597 and the 982nd number in the big array is 2947
    [U-PARN] [PID = 1] the 18th fibonacci number is 2584 and the 981st number in the big array is 2944
    [U-PARN] [PID = 1] the 19th fibonacci number is 4181 and the 980th number in the big array is 2941
    [U-PARN] [PID = 1] the 20th fibonacci number is 6765 and the 979th number in the big array is 2938
    [U-PARN] [PID = 1] the 21st fibonacci number is 10946 and the 978th number in the big array is 2935
    [U-PARN] [PID = 1] the 22nd fibonacci number is 17711 and the 977th number in the big array is 2932
    [U-PARN] [PID = 1] the 23rd fibonacci number is 28657 and the 976th number in the big array is 2929
    [U-PARN] [PID = 1] the 24th fibonacci number is 46368 and the 975th number in the big array is 2926
    [U-PARN] [PID = 1] the 25th fibonacci number is 75025 and the 974th number in the big array is 2923
    [U-PARN] [PID = 1] the 26th fibonacci number is 121393 and the 973rd number in the big array is 2920
    [U-PARN] [PID = 1] the 27th fibonacci number is 196418 and the 972nd number in the big array is 2917
    [U-PARN] [PID = 1] the 28th fibonacci number is 317811 and the 971st number in the big array is 2914
    [U-PARN] [PID = 1] the 29th fibonacci number is 514229 and the 970th number in the big array is 2911
    [U-PARN] [PID = 1] the 30th fibonacci number is 832040 and the 969th number in the big array is 2908
    [U-PARN] [PID = 1] the 31st fibonacci number is 1346269 and the 968th number in the big array is 2905
    [U-PARN] [PID = 1] the 32nd fibonacci number is 2178309 and the 967th number in the big array is 2902
    [U-PARN] [PID = 1] the 33rd fibonacci number is 3524578 and the 966th number in the big array is 2899
    SET [PID = 1, PRIORITY = 5, COUNTER = 5]
    SET [PID = 2, PRIORITY = 9, COUNTER = 9]
    switch to [PID = 2, PRIORITY = 9, COUNTER = 9]
    [S] Store/AMO page fault; sepc = 0x2d8, stval = 0x3fffffff68
    vma = 0xffffffe00032e000, SHARED PAGE [PID = 2], copy 0x80322000 to 0x80334000
    pgtbl = 0x8032a000: map [0x3ffffff000, 0x4000000000) -> [0x80334000, 0x80335000), perm = 0xd7, size = 4096
    [S] Instruction page fault; sepc = 0x1a10, stval = 0x1a10
    vma = 0xffffffe00032b000, pgtbl = 0x8032a000: map [0x1000, 0x2000) -> [0x80322000, 0x80323000), perm = 0xdf, size = 4096
    [U] fork returns 0
    [S] Store/AMO page fault; sepc = 0x1e0, stval = 0x2600
    vma = 0xffffffe00032b000, SHARED PAGE [PID = 2], copy 0x80325000 to 0x80335000
    pgtbl = 0x8032a000: map [0x2000, 0x3000) -> [0x80335000, 0x80336000), perm = 0xdf, size = 4096
    [U-CHLD] [PID = 2] the 0th fibonacci number is 1 and the 999th number in the big array is 2998
    [U-CHLD] [PID = 2] the 1st fibonacci number is 1 and the 998th number in the big array is 2995
    [U-CHLD] [PID = 2] the 2nd fibonacci number is 1 and the 997th number in the big array is 2992
    [U-CHLD] [PID = 2] the 3rd fibonacci number is 2 and the 996th number in the big array is 2989
    [U-CHLD] [PID = 2] the 4th fibonacci number is 3 and the 995th number in the big array is 2986
    [U-CHLD] [PID = 2] the 5th fibonacci number is 5 and the 994th number in the big array is 2983
    [U-CHLD] [PID = 2] the 6th fibonacci number is 8 and the 993rd number in the big array is 2980
    [U-CHLD] [PID = 2] the 7th fibonacci number is 13 and the 992nd number in the big array is 2977
    [U-CHLD] [PID = 2] the 8th fibonacci number is 21 and the 991st number in the big array is 2974
    [U-CHLD] [PID = 2] the 9th fibonacci number is 34 and the 990th number in the big array is 2971
    [U-CHLD] [PID = 2] the 10th fibonacci number is 55 and the 989th number in the big array is 2968
    [U-CHLD] [PID = 2] the 11th fibonacci number is 89 and the 988th number in the big array is 2965
    [U-CHLD] [PID = 2] the 12th fibonacci number is 144 and the 987th number in the big array is 2962
    [U-CHLD] [PID = 2] the 13th fibonacci number is 233 and the 986th number in the big array is 2959
    [U-CHLD] [PID = 2] the 14th fibonacci number is 377 and the 985th number in the big array is 2956
    [U-CHLD] [PID = 2] the 15th fibonacci number is 610 and the 984th number in the big array is 2953
    [U-CHLD] [PID = 2] the 16th fibonacci number is 987 and the 983rd number in the big array is 2950
    [U-CHLD] [PID = 2] the 17th fibonacci number is 1597 and the 982nd number in the big array is 2947
    [U-CHLD] [PID = 2] the 18th fibonacci number is 2584 and the 981st number in the big array is 2944
    [U-CHLD] [PID = 2] the 19th fibonacci number is 4181 and the 980th number in the big array is 2941
    [U-CHLD] [PID = 2] the 20th fibonacci number is 6765 and the 979th number in the big array is 2938
    [U-CHLD] [PID = 2] the 21st fibonacci number is 10946 and the 978th number in the big array is 2935
    [U-CHLD] [PID = 2] the 22nd fibonacci number is 17711 and the 977th number in the big array is 2932
    [U-CHLD] [PID = 2] the 23rd fibonacci number is 28657 and the 976th number in the big array is 2929
    [U-CHLD] [PID = 2] the 24th fibonacci number is 46368 and the 975th number in the big array is 2926
    [U-CHLD] [PID = 2] the 25th fibonacci number is 75025 and the 974th number in the big array is 2923
    [U-CHLD] [PID = 2] the 26th fibonacci number is 121393 and the 973rd number in the big array is 2920
    [U-CHLD] [PID = 2] the 27th fibonacci number is 196418 and the 972nd number in the big array is 2917
    [U-CHLD] [PID = 2] the 28th fibonacci number is 317811 and the 971st number in the big array is 2914
    [U-CHLD] [PID = 2] the 29th fibonacci number is 514229 and the 970th number in the big array is 2911
    [U-CHLD] [PID = 2] the 30th fibonacci number is 832040 and the 969th number in the big array is 2908
    [U-CHLD] [PID = 2] the 31st fibonacci number is 1346269 and the 968th number in the big array is 2905
    [U-CHLD] [PID = 2] the 32nd fibonacci number is 2178309 and the 967th number in the big array is 2902
    [U-CHLD] [PID = 2] the 33rd fibonacci number is 3524578 and the 966th number in the big array is 2899
    [U-CHLD] [PID = 2] the 34th fibonacci number is 5702887 and the 965th number in the big array is 2896
    [U-CHLD] [PID = 2] the 35th fibonacci number is 9227465 and the 964th number in the big array is 2893
    [U-CHLD] [PID = 2] the 36th fibonacci number is 14930352 and the 963rd number in the big array is 2890
    [U-CHLD] [PID = 2] the 37th fibonacci number is 24157817 and the 962nd number in the big array is 2887
    [U-CHLD] [PID = 2] the 38th fibonacci number is 39088169 and the 961st number in the big array is 2884
    switch to [PID = 1, PRIORITY = 5, COUNTER = 5]
    [U-PARN] [PID = 1] the 34th fibonacci number is 5702887 and the 965th number in the big array is 2896
    [U-PARN] [PID = 1] the 35th fibonacci number is 9227465 and the 964th number in the big array is 2893
    [U-PARN] [PID = 1] the 36th fibonacci number is 14930352 and the 963rd number in the big array is 2890
    [U-PARN] [PID = 1] the 37th fibonacci number is 24157817 and the 962nd number in the big array is 2887
    [U-PARN] [PID = 1] the 38th fibonacci number is 39088169 and the 961st number in the big array is 2884
    SET [PID = 1, PRIORITY = 5, COUNTER = 5]
    SET [PID = 2, PRIORITY = 9, COUNTER = 9]
    switch to [PID = 2, PRIORITY = 9, COUNTER = 9]
    [U-CHLD] [PID = 2] the 39th fibonacci number is 63245986 and the 960th number in the big array is 2881
    ```

## 思考题

1. 在 PFH1 测试函数中，缺少了哪种类型的 page fault？尝试修改 PFH1 测试函数，使其能够触发缺少的 page fault。
2. 对于 FORK2 测试函数，在运行时，字符串 `#!c "ZJU Sys3 Lab5"` 位于内存的什么位置？是否在读取的时候产生了 page fault？请给出必要的截图以说明。
3. 画图分析 FORK3 测试中 fork 的过程，并呈现出各个进程的 `var` 应该从几开始输出，再与你的输出进行对比验证。

## 实验提交

同学需要提交实验报告，以及 `project/kernel` 目录下编写的所有代码文件。

**提交前请使用 `make clean` 清除所有构建产物。**

此外，请在报告中展示各 `main` 函数的运行结果。如果没有全部实现，可以只展示部分结果。
