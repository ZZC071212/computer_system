<style>
code {
    font-family: 'Cascadia', SFMono-Regular, Consolas, Menlo, monospace;
}
</style>

# 实验 5：RV64 缺页异常处理及 fork 机制

!!! info "24.05.09 发布、24.05.30 截止提交（三周）"

## 实验目的

- 通过 `vm_area_struct` 数据结构实现对进程**多区域**虚拟内存的管理。
- 在 [Lab4](../lab4) 实现用户态程序的基础上，添加缺页异常处理 **Page Fault Handler**。
- 为进程加入 **fork** 机制，能够支持通过 **fork** 创建新的用户态进程。

## 实验环境

- 与前一实验一致

## 背景知识

### vm_area_struct 介绍

在 Linux 系统中，`vm_area_struct` 是虚拟内存管理的基本单元，保存了有关连续虚拟内存区域（简称 `VMA`）的信息。Linux 具体某一进程的虚拟内存区域映射关系可以通过 [procfs](https://man7.org/linux/man-pages/man5/procfs.5.html) 读取 `/proc/pid/maps` 的内容来获取：

比如，如下一个常规的 `bash` 进程，假设它的进程号为 `7884` ，则通过输入如下命令，就可以查看该进程具体的虚拟地址内存映射情况 (部分信息已省略)。

```shell
#cat /proc/7884/maps
556f22759000-556f22786000 r--p 00000000 08:05 16515165                   /usr/bin/bash
556f22786000-556f22837000 r-xp 0002d000 08:05 16515165                   /usr/bin/bash
556f22837000-556f2286e000 r--p 000de000 08:05 16515165                   /usr/bin/bash
556f2286e000-556f22872000 r--p 00114000 08:05 16515165                   /usr/bin/bash
556f22872000-556f2287b000 rw-p 00118000 08:05 16515165                   /usr/bin/bash
556f22fa5000-556f2312c000 rw-p 00000000 00:00 0                          [heap]
7fb9edb0f000-7fb9edb12000 r--p 00000000 08:05 16517264                   /usr/lib/x86_64-linux-gnu/libnss_files-2.31.so
7fb9edb12000-7fb9edb19000 r-xp 00003000 08:05 16517264                   /usr/lib/x86_64-linux-gnu/libnss_files-2.31.so
...
7ffee5cdc000-7ffee5cfd000 rw-p 00000000 00:00 0                          [stack]
7ffee5dce000-7ffee5dd1000 r--p 00000000 00:00 0                          [vvar]
7ffee5dd1000-7ffee5dd2000 r-xp 00000000 00:00 0                          [vdso]
ffffffffff600000-ffffffffff601000 --xp 00000000 00:00 0                  [vsyscall]
```

从中我们可以读取如下一些有关该进程内虚拟内存映射的关键信息：

- `vm_start`:（第 1 列）指的是该段虚拟内存区域的开始地址
- `vm_end`:（第 2 列）指的是该段虚拟内存区域的结束地址
- `vm_flags`:（第 3 列）该 `vm_area` 的一组权限（rwx）标志，`vm_flags` 的具体取值定义可参考 Linux 源代码的 [linux/mm.h](https://elixir.bootlin.com/linux/v5.15/source/include/linux/mm.h#L265)
- `vm_pgoff`:（第 4 列）虚拟内存映射区域在文件内的偏移量
- `vm_file`:（第 5/6/7 列）分别表示：映射文件所属设备号/指向关联文件结构的指针（如果有的话，一般为文件系统的 inode）/文件名

!!! note "关于虚拟内存区域"
    注意这里记录的 `vm_start` 和 `vm_end` 都是用户态的虚拟地址，并且内核并不会将除了用户程序会用到的内存区域以外的部分添加成为 VMA。

我们注意到，一段内存中的内容可能是由磁盘中的文件映射的。如果这样的内存的 VMA 产生了缺页异常，说明文件中对应的页不在操作系统的 buffer pool 中，或者是由于 buffer pool 的调度策略被换出到磁盘上了。这时候操作系统会用驱动读取硬盘上的内容，放入 buffer pool，然后修改当前 task 的页表来让其能够用原来的地址访问文件内容。而这一切对用户程序来说是完全透明的，除了访问延迟。除了跟文件建立联系以外，VMA 还可能是一块匿名（anonymous）的区域。例如被标成 `[stack]` 的这一块区域，并没有对应的文件。

其它保存在 `vm_area_struct` 中的信息还有：

- `vm_ops`: 该 `vm_area` 中的一组工作函数
- `vm_next/vm_prev`: 同一进程的所有虚拟内存区域由**链表结构**链接起来，这是分别指向前后两个 `vm_area_struct` 结构体的指针

可以发现，原本的 Linux 使用链表对一个 task 内的 VMA 进行管理。但是由于如今一个程序可能体量非常巨大，所以现在的 Linux 已经用虚拟地址为索引来建立红黑树了。

### 缺页异常 Page Fault

在一个启用了虚拟内存的系统上，若正在运行的程序访问当前未由内存管理单元（MMU）映射到虚拟内存的页面，或访问权限不足，则会由计算机硬件引发的缺页异常（Page Fault）。

处理缺页异常通常是操作系统内核的一部分。当处理缺页异常时，操作系统将尝试使所需页面在物理内存中的位置变得可访问（建立新的映射关系到虚拟内存）。而如果在非法访问内存的情况下，发现触发 `Page Fault` 的虚拟内存地址（Bad Address）不在当前进程 `vm_area_struct` 链表所定义的允许访问的虚拟内存地址范围内，或访问位置的权限条件不满足时，缺页异常处理将终止该程序的继续运行。

#### Demand Paging

Demand Paging 遵循的原则是，只有在执行进程需要时，才应将页面放入内存中。这样做的好处是，仅加载执行进程所需的页面，从而节省内存空间。例如，若一个页面从未被访问过，那么它就不需要被放入内存中。

#### RISC-V Page Faults

在 RISC-V 中，当系统运行发生异常时，可通过解析 `scause` 寄存器的值，识别如下三种不同的 Page Fault：

| Interrupt | Exception Code | Description |
| :-: | :-: | --- |
| 0 | 12 | Instruction Page Fault |
| 0 | 13 | Load Page Fault |
| 0 | 15 | Store/AMO Page Fault |

#### 处理 Page Fault 的方式

处理缺页异常时可能所需的信息如下：

- 触发 Page Fault 时访问的虚拟内存地址。当触发 Page Fault 时，`stval` 寄存器被被硬件自动设置为该出错的 VA 地址
- 导致 Page Fault 的类型，保存在 `scause` 寄存器中
    - Exception Code = 12: page fault caused by an instruction fetch
    - Exception Code = 13: page fault caused by a read
    - Exception Code = 15: page fault caused by a write
- 发生 Page Fault 时的指令执行位置，保存在 `sepc` 中
- 当前进程合法的 VMA 映射关系，保存在 `vm_area_struct` 链表中
- 发生异常的虚拟地址对应的 PTE (page table entry) 中记录的信息

总的说来，处理缺页异常需要进行以下步骤：

- 捕获异常
- 寻找当前 task 中导致产生了异常的地址对应的 VMA
- 判断产生异常的原因
    - 如果是匿名区域，那么开辟一页内存，然后把这一页映射到产生异常的 task 的页表中。如果不是，那么首先将硬盘中的内容读入 buffer pool，将 buffer pool 中这段内存映射给 task。
- 返回到产生了该缺页异常的那条指令，并继续执行程序

### Fork 系统调用

Fork 是 Linux 中的重要系统调用，它的作用是将进行了该系统调用的 task 完整地复制一份，并加入 Ready Queue。这样在下一次调度发生时，调度器就能够发现多了一个 task。从这时候开始，新的 task 就可能被正式从 Ready 调度到 Running，而开始执行了。需留意，fork 具有以下特点：

- Fork 通过复制当前进程创建一个新的进程，新进程称为子进程，而原进程称为父进程。
- 子进程和父进程在不同的内存空间上运行。
- Fork 成功时，父进程返回子进程的 PID，子进程返回 `0`；失败时，父进程返回 `-1`。
- 创建的子 task 需要深拷贝 `task_struct`，调整自己的页表、栈和 CSR 寄存器等信息，复制一份在用户态会用到的内存信息（用户态的栈、程序的代码和数据等），并且将自己伪装成是一个因为调度而加入了 Ready Queue 的普通程序来等待调度。在调度发生时，这个新 task 就像是原本就在等待调度一样，被调度器选择并调度。
- Linux 中使用了 `copy-on-write` 机制，fork 创建的子进程首先与父进程共享物理内存空间，直到父子进程有修改内存的操作发生时再为子进程分配物理内存。本次实验中将实现一个简单的 COW 机制。

#### Fork 在 Linux 中的实际应用

Linux 的另一个重要系统调用是 `exec`，它的作用是将进行了该系统调用的 task 换成另一个 task。这两个系统调用一起，支撑起了 Linux 处理多任务的基础。当我们在 shell 里键入一个程序的目录时，shell（比如 zsh 或 bash）会先进行一次 fork，这时候相当于有两个 shell 正在运行。然后其中的一个 shell 根据 fork 的返回值（是否为 0），发现自己和原本的 shell 不同，再调用 exec 来把自己给换成另一个程序，这样 shell 外的程序就得以执行了。

## 实验步骤

!!! warning "关于内存分配"
    有些同学可能实际上是基于系统二 lab6 的 kernel 进行我们现在的实验的。因为 lab6 里面修改了物理内存的大小，可能不足够支持我们当前的实验。建议将内存改回到 128MB。此外，新的 `mm` 模块中的 buddy system 分配速度应该会比之前快很多。

### 实现缺页异常

#### 准备工作

- 此次实验基于 Lab4 同学所实现的代码进行。
- 从 repo 同步以下文件，并按照以下步骤将这些文件正确放置。

    ```text
    src/lab5
    ├── arch
    │   └── riscv
    │       ├── include
    │       │   └── mm.h
    │       └── kernel
    │           └── mm.c
    └── user
        └── getpid.c
    ```

- 在 `user/getpid.c` 中我们分两个部分，分别放置了两个与四个 `main` 函数，用于检测同学们实验的正确性。在下面的文档中，将会把前两个称为 `PFH main #i`，后四个称为 `Fork main #i`。

#### 实现虚拟内存管理功能

修改 `proc.h`，添加如下内容：

```c
/* vm_area_struct vm_flags */
#define VM_READ     0x00000001
#define VM_WRITE    0x00000002
#define VM_EXEC     0x00000004

struct vm_area_struct {
    struct mm_struct *vm_mm;    /* The mm_struct we belong to. */
    uint64 vm_start;            /* Our start address within vm_mm. */
    uint64 vm_end;              /* The first byte after our end address
                                   within vm_mm. */

    /* linked list of VM areas per task, sorted by address */
    struct vm_area_struct *vm_next, *vm_prev;

    uint64 vm_flags;            /* Flags as listed above. */
};

struct mm_struct {
    struct vm_area_struct *mmap;    /* list of VMAs */
};

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

每一个 `vm_area_struct` 都对应于进程地址空间的唯一区间。注意我们这里的 `vm_flag` 标志位和 PTE 的标志位并没有按 bit 进行对应，请同学们仔细对照 bit 的位置，以免出现问题。

此外，为了支持 `Demand Paging`，我们需要支持对 `vm_area_struct` 的添加，查找：

- `find_vma` 函数：实现对 `vm_area_struct` 的查找
    - 根据传入的地址 `addr`，遍历链表 `mm` 包含的 VMA 链表，找到该地址所在的 `vm_area_struct`
    - 如果链表中所有的 `vm_area_struct` 都不包含该地址，则返回 `NULL`

    ```c
    /*
    * @mm          : current thread's mm_struct
    * @address     : the va to look up
    *
    * @return      : the VMA if found or NULL if not found
    */
    struct vm_area_struct *find_vma(struct mm_struct *mm, uint64 addr);
    ```

- `do_mmap` 函数：实现 `vm_area_struct` 的添加
    - 新建 `vm_area_struct` 结构体，根据传入的参数对结构体赋值，并添加到 `mm` 指向的 VMA 链表中
    - 需要检查传入的参数 `[addr, addr + length)` 是否与 VMA 链表中已有的 `vm_area_struct` 重叠。如果存在重叠，则需要调用 `get_unmapped_area` 函数寻找一个其它合适的位置进行映射

    ```c
    /*
    * @mm     : current thread's mm_struct
    * @addr   : the suggested va to map
    * @length : memory size to map
    * @prot   : protection
    *
    * @return : start va
    */
    uint64 do_mmap(struct mm_struct *mm, uint64 addr, uint64 length, int prot);
    ```

- `get_unmapped_area` 函数：用于解决 `do_mmap` 中 `addr` 与已有 VMA 重叠的情况
    - 我们采用最简单的暴力搜索方法来寻找未映射的长度为 `length`（按页对齐）的虚拟地址区域
    - 从 `0` 地址开始向上以 `PGSIZE` 为单位遍历，直到遍历到连续 `length` 长度内均无已有映射的地址区域，将该区域的首地址返回

    ```c
    uint64 get_unmapped_area(struct mm_struct *mm, uint64 length);
    ```

#### 修改 task_init 函数

Linux 在 Page Fault Handler 中需要考虑多种情况。我们的实验经过简化，只需要根据 `vm_area_struct` 中的 `vm_flags` 来确定当前发生了什么样的错误，并且需要如何处理。在初始化一个 task 时我们既不分配内存，又不更改页表项来建立映射。回退到用户态进行程序执行的时候就会因为没有映射而发生 Page Fault，进入我们的 Page Fault Handler 后，我们再分配空间（按需要拷贝内容）进行映射。

根据这种思想，在调用 `do_mmap` 映射页面时，我们不直接对页表进行修改，而只在该进程所属的 `mm->mmap` 链表上添加一个 VMA 记录。之后，当我们真正访问这个页面时，会触发缺页异常。在缺页异常处理函数中，我们需要根据缺页的地址，找到该地址对应的 VMA，根据 VMA 中的信息对页表进行映射。

因此，修改 `task_init` 函数代码，更改为 `Demand Paging`：

- 删除之前实验中对 `uapp`、栈进行映射的代码
- 调用 `do_mmap` 函数，为进程的 VMA 链表添加新的 `vm_area_struct` 结构，从而建立用户进程的虚拟地址空间信息，包括两个区域：
    - 代码区域，该区域从虚拟地址 `USER_START` 开始，大小为 `uapp_end - uapp_start`，权限为 `VM_READ | VM_WRITE | VM_EXEC`
    - 用户栈，范围为 `[USER_END - PGSIZE, USER_END)` ，权限为 `VM_READ | VM_WRITE`

在完成上述修改之后，如果运行代码，我们可以截获一个 Page Fault，如下所示：

```bash
# Instruction Page Fault
Page fault at 0000000000000000, badaddr is 0000000000000000, scause: 000000000000000c
```

#### 实现 Page Fault Handler

在中断异常处理逻辑中实现 Page Fault 的检测与处理：

- 修改 `trap.c`，添加捕获 Page Fault 的逻辑。
- 当捕获了 `Page Fault` 之后，需要实现缺页异常的处理函数 `do_page_fault`。如上面展示的 Instruction Page Fault，对这个异常需要同学们新分配一个页，并拷贝 `uapp` 的对应内容到新分配的页内。
- 其他类型的缺页异常也可以参考如上的处理方式。

```c
void do_page_fault(struct pt_regs *regs) {
    /*
     1. 通过 stval 获得访问出错的虚拟内存地址（Bad Address）
     2. 通过 scause 获得当前的 Page Fault 类型
     3. 通过 find_vm() 找到对应的 vm_area_struct
     4. 分配一个页，将这个页映射到对应的用户地址空间
     5. 通过 vm_area_struct 的 vm_flags 对当前的 Page Fault 类型进行检查并处理
         5.1 Instruction Page Fault      -> VM_EXEC
         5.2 Load Page Fault             -> VM_READ
         5.3 Store Page Fault            -> VM_WRITE
     6. 最后调用 create_mapping 对页表进行映射
    */
}
```

至此，同学们已经完成了缺页异常处理的部分，建议同学们使用 `PFH main #1` 与 `PFH main #2` 来检测自己实现的正确性。

### 实现 fork 机制

#### 准备工作

- 在 `user/getpid.c` 中有四个 `main` 函数，在不同程度上检测同学们实现的 fork 功能是否正确。同学们可以通过启用不同的 `main` 函数来测试阶段性功能是否正确实现。
- 新提供的 `mm` 提供了用于对页面引用计数的接口，从而方便同学们实现 fork 时的页面共享机制。新定义的内容如下：

    ```c
    uint64 get_page(uint64 va); // 通过虚拟地址增加页面引用计数
                                // 成功返回 0，失败返回 1
    void put_page(uint64 va);   // 通过虚拟地址减少页面引用计数
    ```

    逻辑不算复杂，同学们可以参考 `mm.c` 中的实现进行理解。其中 `ref_cnt` 用于记录页面的引用计数，`page_ref_inc` 和 `page_ref_dec` 函数分别用于增加和减少页面的引用计数。
- 在 `proc.c` 中修改 `task_init` 函数，使其仅初始化一个进程，之后其余的进程均通过 fork 创建（暂时设置为 `NULL`）。
- 在 [Lab3](../lab3) 中，我们曾经提及 RISC-V Sv39 模式的页表项：

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

- 由于在实验过程中需要 fork 比较多的进程，因此需要修改 `NR_TASKS` 至少为 9 (1 + 8)。
- 为了方便实验中深拷贝页表，推荐同学们写一个 `walk_page_table` 的函数，用于遍历页表，找到对应的页表项。

#### 添加 fork 相关声明与定义

Fork 所调用的系统调用为 `SYS_CLONE`，系统调用号为 220。在 `syscall.h` 中添加如下内容：

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

- 选择一个空闲的 PID 作为子进程的 PID，将其放置到 `task` 数组中
- 时间片设置为 0 即可，等待调度器重新分配
- 当子进程被调度时，`__switch_to` 会从子进程的 `thread` 等成员变量中取出在 `do_fork` 中设置好的成员变量，并装载到寄存器中，因此需要正确设置 `thread` 结构体的内容：
    - 设置 `thread.ra` 为 `ret_from_fork`（详见[设置子进程返回逻辑](#_12)）
    - 设置 `thread.sp` 为子进程的内核栈 `sp`（可以根据父进程 `task_struct` 地址、父进程 `sp` 与子进程 `task_struct` 地址计算得到）
- 在 `ret_from_fork` 中，我们将会根据内核栈中保存的 `pt_regs` 中对寄存器状态进行恢复。同学们可以考虑子进程的返回值 `a0`、栈指针、返回地址等内容。

#### 拷贝用户态进程状态

抽丝剥茧，我们现在剩下的主要任务就是处理子进程在用户态下的页表和内存管理了。

先从比较简单的内存管理开始吧。我们知道，子进程的内存管理结构 `mm` 既需要和父进程一致，又不能影响父进程，因此我们只需要**深拷贝**一份父进程的 `mm` 即可。请注意，这是一个**链表**，同学们需要正确地处理链表的深拷贝。

接着，让我们处理页表的拷贝。为了能在内核态正确运行，分配一个页给根页表后，复制内核根页表 `swapper_pg_dir` 必不可少。接下来，我们需要让用户态程序能够正确的找到虚拟地址对应的物理地址。如果我们不需要实现 COW 机制，那么我们只需要通过遍历 `mm` 中保存的 VMA，将每个已经在父进程中映射的页在子进程中拷贝并映射即可；而为了实现 COW 机制，在此处，只需要将拷贝的过程修改为：使用 `get_page` 函数增加页面引用计数，然后将页表项的写位清除、共享位（如上定义的 `PTE_S`）置位。当然，也请别忘了在这之后对子进程的页表进行映射。

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

虽然测试函数比较多，但是为了同学们检测方便起见，我们在这里将给出所有 `PFH main #i` 与 `Fork main #i` 函数的输出示例。对于 `Fork main #i`，需要同学们在 COW 发生时打印一些信息，以便于检查 COW 是否正确实现。

#### PFH main #i

这部分里，请同学们将 `NR_TASKS` 修改为至少为 5，即 1 + 4，并且在 `task_init` 中初始化除了 idle task 之外的其他 4 个进程。

```bash
# PFH main #1
OpenSBI v0.9
...
Boot HART MIDELEG         : 0x0000000000000222
Boot HART MEDELEG         : 0x000000000000b109
...buddy_init done!
...proc_init done!
2024 ZJU Computer System III
[S-MODE] SET [PID = 4 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 3 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[S-MODE] Page fault at 0000000000000000, badaddr is 0000000000000000, scause: 000000000000000c
[S-MODE] Page fault at 0000000000000090, badaddr is 0000003ffffffff8, scause: 000000000000000f
[U-MODE] pid: 1, sp is 0000003ffffffff0
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[S-MODE] Page fault at 0000000000000000, badaddr is 0000000000000000, scause: 000000000000000c
[S-MODE] Page fault at 0000000000000090, badaddr is 0000003ffffffff8, scause: 000000000000000f
[U-MODE] pid: 2, sp is 0000003ffffffff0
[U-MODE] pid: 2, sp is 0000003ffffffff0
[S-MODE] switch to [PID = 4, COUNTER = 4, PRIORITY = 4]
[S-MODE] Page fault at 0000000000000000, badaddr is 0000000000000000, scause: 000000000000000c
[S-MODE] Page fault at 0000000000000090, badaddr is 0000003ffffffff8, scause: 000000000000000f
[U-MODE] pid: 4, sp is 0000003ffffffff0
[U-MODE] pid: 4, sp is 0000003ffffffff0
[S-MODE] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[S-MODE] Page fault at 0000000000000000, badaddr is 0000000000000000, scause: 000000000000000c
[S-MODE] Page fault at 0000000000000090, badaddr is 0000003ffffffff8, scause: 000000000000000f
[U-MODE] pid: 3, sp is 0000003ffffffff0
[U-MODE] pid: 3, sp is 0000003ffffffff0
[S-MODE] SET [PID = 4 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 3 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U-MODE] pid: 2, sp is 0000003ffffffff0
[S-MODE] switch to [PID = 4, COUNTER = 4, PRIORITY = 4]
[U-MODE] pid: 4, sp is 0000003ffffffff0
[S-MODE] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[U-MODE] pid: 3, sp is 0000003ffffffff0
[U-MODE] pid: 3, sp is 0000003ffffffff0
```

```bash
# PFH main #2
OpenSBI v0.9
   ____                    _____ ____ _____
  / __ \                  / ____|  _ \_   _|
 | |  | |_ __   ___ _ __ | (___ | |_) || |
 | |  | | '_ \ / _ \ '_ \ \___ \|  _ < | |
 | |__| | |_) |  __/ | | |____) | |_) || |_
  \____/| .__/ \___|_| |_|_____/|____/_____|
        | |
        |_|

Platform Name             : riscv-virtio,qemu
Platform Features         : timer,mfdeleg
Platform HART Count       : 1
Firmware Base             : 0x80000000
Firmware Size             : 100 KB
Runtime SBI Version       : 0.2

Domain0 Name              : root
Domain0 Boot HART         : 0
Domain0 HARTs             : 0*
Domain0 Region00          : 0x0000000080000000-0x000000008001ffff ()
Domain0 Region01          : 0x0000000000000000-0xffffffffffffffff (R,W,X)
Domain0 Next Address      : 0x0000000080200000
Domain0 Next Arg1         : 0x0000000087000000
Domain0 Next Mode         : S-mode
Domain0 SysReset          : yes

Boot HART ID              : 0
Boot HART Domain          : root
Boot HART ISA             : rv64imafdcsu
Boot HART Features        : scounteren,mcounteren,time
Boot HART PMP Count       : 16
Boot HART PMP Granularity : 4
Boot HART PMP Address Bits: 54
Boot HART MHPM Count      : 0
Boot HART MHPM Count      : 0
Boot HART MIDELEG         : 0x0000000000000222
Boot HART MEDELEG         : 0x000000000000b109
...buddy_init done!
...proc_init done!
2024 ZJU Computer System III
[S-MODE] SET [PID = 4 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 3 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[DEBUG] Page fault at 0000000000000000, badaddr is 0000000000000000, scause: 000000000000000c
[DEBUG] Page fault at 0000000000000090, badaddr is 0000003ffffffff8, scause: 000000000000000f
[DEBUG] Page fault at 00000000000000ac, badaddr is 00000000000017c0, scause: 000000000000000d
[U-MODE] pid: 1, increment: 0
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[DEBUG] Page fault at 0000000000000000, badaddr is 0000000000000000, scause: 000000000000000c
[DEBUG] Page fault at 0000000000000090, badaddr is 0000003ffffffff8, scause: 000000000000000f
[DEBUG] Page fault at 00000000000000ac, badaddr is 00000000000017c0, scause: 000000000000000d
[U-MODE] pid: 2, increment: 0
[U-MODE] pid: 2, increment: 1
[U-MODE] pid: 2, increment: 2
[S-MODE] switch to [PID = 4, COUNTER = 4, PRIORITY = 4]
[DEBUG] Page fault at 0000000000000000, badaddr is 0000000000000000, scause: 000000000000000c
[DEBUG] Page fault at 0000000000000090, badaddr is 0000003ffffffff8, scause: 000000000000000f
[DEBUG] Page fault at 00000000000000ac, badaddr is 00000000000017c0, scause: 000000000000000d
[U-MODE] pid: 4, increment: 0
[U-MODE] pid: 4, increment: 1
[U-MODE] pid: 4, increment: 2
[S-MODE] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[DEBUG] Page fault at 0000000000000000, badaddr is 0000000000000000, scause: 000000000000000c
[DEBUG] Page fault at 0000000000000090, badaddr is 0000003ffffffff8, scause: 000000000000000f
[DEBUG] Page fault at 00000000000000ac, badaddr is 00000000000017c0, scause: 000000000000000d
[U-MODE] pid: 3, increment: 0
[U-MODE] pid: 3, increment: 1
[U-MODE] pid: 3, increment: 2
[S-MODE] SET [PID = 4 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 3 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[U-MODE] pid: 1, increment: 1
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U-MODE] pid: 2, increment: 3
[U-MODE] pid: 2, increment: 4
[S-MODE] switch to [PID = 4, COUNTER = 4, PRIORITY = 4]
[U-MODE] pid: 4, increment: 3
[U-MODE] pid: 4, increment: 4
[S-MODE] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[U-MODE] pid: 3, increment: 3
[U-MODE] pid: 3, increment: 4
[U-MODE] pid: 3, increment: 5
```

#### Fork main #i

这部分里，请同学们将 `NR_TASKS` 修改为至少为 9，即 1 + 8，并且在 `task_init` 中只初始化 idle task 之外的 1 个进程，其他的暂时置为 `NULL`。

```bash
# Fork main #1
OpenSBI v0.9
...
...buddy_init done!
...proc_init done!
2024 ZJU Computer System III
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[DEBUG] Page fault at 0000000000000000, badaddr is 0000000000000000, scause: 000000000000000c
[DEBUG] Page fault at 00000000000000c4, badaddr is 0000003ffffffff8, scause: 000000000000000f
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffc8, scause: 000000000000000f
[S-MODE] PID = 1, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000150, badaddr is 00000000000008a8, scause: 000000000000000f
[S-MODE] PID = 1, Copy on Write on page 0000000000000000
[U-PARENT] pid: 1 is running! global_variable: 0
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[U-PARENT] pid: 1 is running! global_variable: 1
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffc8, scause: 000000000000000f
[S-MODE] PID = 2, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 000000000000010c, badaddr is 00000000000008a8, scause: 000000000000000f
[S-MODE] PID = 2, Copy on Write on page 0000000000000000
[U-CHILD] pid: 2 is running! global_variable: 0
[U-CHILD] pid: 2 is running! global_variable: 1
[U-CHILD] pid: 2 is running! global_variable: 2
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U-CHILD] pid: 2 is running! global_variable: 3
[U-CHILD] pid: 2 is running! global_variable: 4
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[U-PARENT] pid: 1 is running! global_variable: 2
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U-CHILD] pid: 2 is running! global_variable: 5
[U-CHILD] pid: 2 is running! global_variable: 6
[U-CHILD] pid: 2 is running! global_variable: 7
```

```bash
# Fork main #2
OpenSBI v0.9
...
...buddy_init done!
...proc_init done!
2024 ZJU Computer System III
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[DEBUG] Page fault at 0000000000000000, badaddr is 0000000000000000, scause: 000000000000000c
[DEBUG] Page fault at 00000000000000c4, badaddr is 0000003ffffffff8, scause: 000000000000000f
[DEBUG] Page fault at 000000000000092c, badaddr is 0000000000002ac8, scause: 000000000000000f
[U] pid: 1 is running! global_variable: 0
[U] pid: 1 is running! global_variable: 1
[U] pid: 1 is running! global_variable: 2
[DEBUG] Page fault at 0000000000000140, badaddr is 0000000000001ac8, scause: 000000000000000f
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffc8, scause: 000000000000000f
[S-MODE] PID = 1, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 000000000000092c, badaddr is 0000000000002ac8, scause: 000000000000000f
[S-MODE] PID = 1, Copy on Write on page 0000000000002000
[U-PARENT] pid: 1 is running! Message: Sys3-Lab5
[DEBUG] Page fault at 00000000000002dc, badaddr is 0000000000000ac0, scause: 000000000000000f
[S-MODE] PID = 1, Copy on Write on page 0000000000000000
[U-PARENT] pid: 1 is running! global_variable: 3
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[U-PARENT] pid: 1 is running! global_variable: 4
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffc8, scause: 000000000000000f
[S-MODE] PID = 2, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 000000000000092c, badaddr is 0000000000002ac8, scause: 000000000000000f
[S-MODE] PID = 2, Copy on Write on page 0000000000002000
[U-CHILD] pid: 2 is running! Message: Sys3-Lab5
[DEBUG] Page fault at 0000000000000274, badaddr is 0000000000000ac0, scause: 000000000000000f
[S-MODE] PID = 2, Copy on Write on page 0000000000000000
[U-CHILD] pid: 2 is running! global_variable: 3
[U-CHILD] pid: 2 is running! global_variable: 4
[U-CHILD] pid: 2 is running! global_variable: 5
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U-CHILD] pid: 2 is running! global_variable: 6
[U-CHILD] pid: 2 is running! global_variable: 7
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[U-PARENT] pid: 1 is running! global_variable: 5
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U-CHILD] pid: 2 is running! global_variable: 8
[U-CHILD] pid: 2 is running! global_variable: 9
[U-CHILD] pid: 2 is running! global_variable: 10
```

```bash
# Fork main #3
OpenSBI v0.9
...
...buddy_init done!
...proc_init done!
2024 ZJU Computer System III
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[DEBUG] Page fault at 0000000000000000, badaddr is 0000000000000000, scause: 000000000000000c
[DEBUG] Page fault at 00000000000000c4, badaddr is 0000003ffffffff8, scause: 000000000000000f
[U] pid: 1 is running! global_variable: 0
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffd8, scause: 000000000000000f
[S-MODE] PID = 1, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffd8, scause: 000000000000000f
[S-MODE] PID = 1, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000134, badaddr is 0000000000000888, scause: 000000000000000f
[S-MODE] PID = 1, Copy on Write on page 0000000000000000
[U] pid: 1 is running! global_variable: 1
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffd8, scause: 000000000000000f
[S-MODE] PID = 1, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000170, badaddr is 0000000000000888, scause: 000000000000000f
[S-MODE] PID = 1, Copy on Write on page 0000000000000000
[U] pid: 1 is running! global_variable: 2
[S-MODE] SET [PID = 4 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 3 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[U] pid: 1 is running! global_variable: 3
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffd8, scause: 000000000000000f
[S-MODE] PID = 2, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffd8, scause: 000000000000000f
[S-MODE] PID = 2, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000134, badaddr is 0000000000000888, scause: 000000000000000f
[S-MODE] PID = 2, Copy on Write on page 0000000000000000
[U] pid: 2 is running! global_variable: 1
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffd8, scause: 000000000000000f
[S-MODE] PID = 2, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000170, badaddr is 0000000000000888, scause: 000000000000000f
[S-MODE] PID = 2, Copy on Write on page 0000000000000000
[U] pid: 2 is running! global_variable: 2
[U] pid: 2 is running! global_variable: 3
[U] pid: 2 is running! global_variable: 4
[S-MODE] switch to [PID = 4, COUNTER = 4, PRIORITY = 4]
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffd8, scause: 000000000000000f
[S-MODE] PID = 4, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000170, badaddr is 0000000000000888, scause: 000000000000000f
[S-MODE] PID = 4, Copy on Write on page 0000000000000000
[U] pid: 4 is running! global_variable: 2
[U] pid: 4 is running! global_variable: 3
[U] pid: 4 is running! global_variable: 4
[S-MODE] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffd8, scause: 000000000000000f
[S-MODE] PID = 3, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000134, badaddr is 0000000000000888, scause: 000000000000000f
[S-MODE] PID = 3, Copy on Write on page 0000000000000000
[U] pid: 3 is running! global_variable: 1
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffd8, scause: 000000000000000f
[S-MODE] PID = 3, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000170, badaddr is 0000000000000888, scause: 000000000000000f
[S-MODE] PID = 3, Copy on Write on page 0000000000000000
[U] pid: 3 is running! global_variable: 2
[U] pid: 3 is running! global_variable: 3
[U] pid: 3 is running! global_variable: 4
[S-MODE] SET [PID = 7 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 6 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 5 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 4 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 3 PRIORITY = 5 COUNTER = 5]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U] pid: 2 is running! global_variable: 5
[U] pid: 2 is running! global_variable: 6
[S-MODE] switch to [PID = 4, COUNTER = 4, PRIORITY = 4]
[U] pid: 4 is running! global_variable: 5
[U] pid: 4 is running! global_variable: 6
[S-MODE] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[U] pid: 3 is running! global_variable: 5
[U] pid: 3 is running! global_variable: 6
[U] pid: 3 is running! global_variable: 7
[S-MODE] switch to [PID = 5, COUNTER = 5, PRIORITY = 5]
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffd8, scause: 000000000000000f
[S-MODE] PID = 5, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000134, badaddr is 0000000000000888, scause: 000000000000000f
[S-MODE] PID = 5, Copy on Write on page 0000000000000000
[U] pid: 5 is running! global_variable: 1
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffd8, scause: 000000000000000f
[S-MODE] PID = 5, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000170, badaddr is 0000000000000888, scause: 000000000000000f
[S-MODE] PID = 5, Copy on Write on page 0000000000000000
[U] pid: 5 is running! global_variable: 2
[U] pid: 5 is running! global_variable: 3
[U] pid: 5 is running! global_variable: 4
[S-MODE] switch to [PID = 6, COUNTER = 5, PRIORITY = 5]
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffd8, scause: 000000000000000f
[S-MODE] PID = 6, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000170, badaddr is 0000000000000888, scause: 000000000000000f
[S-MODE] PID = 6, Copy on Write on page 0000000000000000
[U] pid: 6 is running! global_variable: 2
[U] pid: 6 is running! global_variable: 3
[U] pid: 6 is running! global_variable: 4
[S-MODE] switch to [PID = 7, COUNTER = 5, PRIORITY = 5]
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffd8, scause: 000000000000000f
[S-MODE] PID = 7, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000170, badaddr is 0000000000000888, scause: 000000000000000f
[S-MODE] PID = 7, Copy on Write on page 0000000000000000
[U] pid: 7 is running! global_variable: 2
[U] pid: 7 is running! global_variable: 3
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
[U] pid: 1 is running! global_variable: 4
[S-MODE] switch to [PID = 8, COUNTER = 2, PRIORITY = 2]
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffd8, scause: 000000000000000f
[S-MODE] PID = 8, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000170, badaddr is 0000000000000888, scause: 000000000000000f
[S-MODE] PID = 8, Copy on Write on page 0000000000000000
[U] pid: 8 is running! global_variable: 2
[U] pid: 8 is running! global_variable: 3
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U] pid: 2 is running! global_variable: 7
[U] pid: 2 is running! global_variable: 8
[U] pid: 2 is running! global_variable: 9
[S-MODE] switch to [PID = 4, COUNTER = 4, PRIORITY = 4]
[U] pid: 4 is running! global_variable: 7
[U] pid: 4 is running! global_variable: 8
[U] pid: 4 is running! global_variable: 9
[S-MODE] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[U] pid: 3 is running! global_variable: 8
[U] pid: 3 is running! global_variable: 9
[U] pid: 3 is running! global_variable: 10
[S-MODE] switch to [PID = 5, COUNTER = 5, PRIORITY = 5]
[U] pid: 5 is running! global_variable: 5
[U] pid: 5 is running! global_variable: 6
[U] pid: 5 is running! global_variable: 7
[S-MODE] switch to [PID = 6, COUNTER = 5, PRIORITY = 5]
[U] pid: 6 is running! global_variable: 5
[U] pid: 6 is running! global_variable: 6
[U] pid: 6 is running! global_variable: 7
[S-MODE] switch to [PID = 7, COUNTER = 5, PRIORITY = 5]
[U] pid: 7 is running! global_variable: 6
[U] pid: 7 is running! global_variable: 7
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
[U] pid: 8 is running! global_variable: 4
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U] pid: 2 is running! global_variable: 10
[U] pid: 2 is running! global_variable: 11
[S-MODE] switch to [PID = 4, COUNTER = 4, PRIORITY = 4]
[U] pid: 4 is running! global_variable: 10
[U] pid: 4 is running! global_variable: 11
[S-MODE] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[U] pid: 3 is running! global_variable: 11
[U] pid: 3 is running! global_variable: 12
[U] pid: 3 is running! global_variable: 13
[S-MODE] switch to [PID = 5, COUNTER = 5, PRIORITY = 5]
[U] pid: 5 is running! global_variable: 8
[U] pid: 5 is running! global_variable: 9
[U] pid: 5 is running! global_variable: 10
[S-MODE] switch to [PID = 6, COUNTER = 5, PRIORITY = 5]
[U] pid: 6 is running! global_variable: 8
[U] pid: 6 is running! global_variable: 9
[U] pid: 6 is running! global_variable: 10
[S-MODE] switch to [PID = 7, COUNTER = 5, PRIORITY = 5]
[U] pid: 7 is running! global_variable: 8
[U] pid: 7 is running! global_variable: 9
[U] pid: 7 is running! global_variable: 10
```

!!! note "关于 Fork main #4"
    这是由某位 20 级学长从 OS 传下来的测试代码，用于分两个进程进行斐波那契数列的计算。读者应保证 `U-PARENT` 和 `U-CHILD` 对于每个斐波那契数的输出是正确的。

```bash
# Fork main #4
OpenSBI v0.9
...
...buddy_init done!
...proc_init done!
2024 ZJU Computer System III
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[DEBUG] Page fault at 0000000000000000, badaddr is 0000000000000000, scause: 000000000000000c
[DEBUG] Page fault at 000000000000014c, badaddr is 0000003ffffffff8, scause: 000000000000000f
[DEBUG] Page fault at 0000000000000180, badaddr is 0000000000001000, scause: 000000000000000f
[DEBUG] Page fault at 0000000000000180, badaddr is 0000000000002000, scause: 000000000000000f
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffb8, scause: 000000000000000f
[S-MODE] PID = 1, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000978, badaddr is 0000000000002a50, scause: 000000000000000f
[S-MODE] PID = 1, Copy on Write on page 0000000000002000
[U] fork returns 2
[U-PARENT] pid: 1 is running! the 0th fibonacci number is 1 and the number @ 999 in the large array is 999
[DEBUG] Page fault at 0000000000000338, badaddr is 0000000000000b08, scause: 000000000000000f
[S-MODE] PID = 1, Copy on Write on page 0000000000000000
[U-PARENT] pid: 1 is running! the 1th fibonacci number is 1 and the number @ 998 in the large array is 998
[U-PARENT] pid: 1 is running! the 2th fibonacci number is 1 and the number @ 997 in the large array is 997
[U-PARENT] pid: 1 is running! the 3th fibonacci number is 2 and the number @ 996 in the large array is 996
[U-PARENT] pid: 1 is running! the 4th fibonacci number is 3 and the number @ 995 in the large array is 995
[U-PARENT] pid: 1 is running! the 5th fibonacci number is 5 and the number @ 994 in the large array is 994
[U-PARENT] pid: 1 is running! the 6th fibonacci number is 8 and the number @ 993 in the large array is 993
[U-PARENT] pid: 1 is running! the 7th fibonacci number is 13 and the number @ 992 in the large array is 992
[U-PARENT] pid: 1 is running! the 8th fibonacci number is 21 and the number @ 991 in the large array is 991
[U-PARENT] pid: 1 is running! the 9th fibonacci number is 34 and the number @ 990 in the large array is 990
[U-PARENT] pid: 1 is running! the 10th fibonacci number is 55 and the number @ 989 in the large array is 989
[U-PARENT] pid: 1 is running! the 11th fibonacci number is 89 and the number @ 988 in the large array is 988
[U-PARENT] pid: 1 is running! the 12th fibonacci number is 144 and the number @ 987 in the large array is 987
[U-PARENT] pid: 1 is running! the 13th fibonacci number is 233 and the number @ 986 in the large array is 986
[U-PARENT] pid: 1 is running! the 14th fibonacci number is 377 and the number @ 985 in the large array is 985
[U-PARENT] pid: 1 is running! the 15th fibonacci number is 610 and the number @ 984 in the large array is 984
[U-PARENT] pid: 1 is running! the 16th fibonacci number is 987 and the number @ 983 in the large array is 983
[U-PARENT] pid: 1 is running! the 17th fibonacci number is 1597 and the number @ 982 in the large array is 982
[U-PARENT] pid: 1 is running! the 18th fibonacci number is 2584 and the number @ 981 in the large array is 981
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[U-PARENT] pid: 1 is running! the 19th fibonacci number is 4181 and the number @ 980 in the large array is 980
[U-PARENT] pid: 1 is running! the 20th fibonacci number is 6765 and the number @ 979 in the large array is 979
[U-PARENT] pid: 1 is running! the 21th fibonacci number is 10946 and the number @ 978 in the large array is 978
[U-PARENT] pid: 1 is running! the 22th fibonacci number is 17711 and the number @ 977 in the large array is 977
[U-PARENT] pid: 1 is running! the 23th fibonacci number is 28657 and the number @ 976 in the large array is 976
[U-PARENT] pid: 1 is running! the 24th fibonacci number is 46368 and the number @ 975 in the large array is 975
[U-PARENT] pid: 1 is running! the 25th fibonacci number is 75025 and the number @ 974 in the large array is 974
[U-PARENT] pid: 1 is running! the 26th fibonacci number is 121393 and the number @ 973 in the large array is 973
[U-PARENT] pid: 1 is running! the 27th fibonacci number is 196418 and the number @ 972 in the large array is 972
[U-PARENT] pid: 1 is running! the 28th fibonacci number is 317811 and the number @ 971 in the large array is 971
[U-PARENT] pid: 1 is running! the 29th fibonacci number is 514229 and the number @ 970 in the large array is 970
[U-PARENT] pid: 1 is running! the 30th fibonacci number is 832040 and the number @ 969 in the large array is 969
[U-PARENT] pid: 1 is running! the 31th fibonacci number is 1346269 and the number @ 968 in the large array is 968
[U-PARENT] pid: 1 is running! the 32th fibonacci number is 2178309 and the number @ 967 in the large array is 967
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[DEBUG] Page fault at 0000000000000054, badaddr is 0000003fffffffb8, scause: 000000000000000f
[S-MODE] PID = 2, Copy on Write on page 0000003ffffff000
[DEBUG] Page fault at 0000000000000978, badaddr is 0000000000002a50, scause: 000000000000000f
[S-MODE] PID = 2, Copy on Write on page 0000000000002000
[U] fork returns 0
[U-CHILD] pid: 2 is running! the 0th fibonacci number is 1 and the number @ 999 in the large array is 999
[DEBUG] Page fault at 0000000000000278, badaddr is 0000000000000b08, scause: 000000000000000f
[S-MODE] PID = 2, Copy on Write on page 0000000000000000
[U-CHILD] pid: 2 is running! the 1th fibonacci number is 1 and the number @ 998 in the large array is 998
[U-CHILD] pid: 2 is running! the 2th fibonacci number is 1 and the number @ 997 in the large array is 997
[U-CHILD] pid: 2 is running! the 3th fibonacci number is 2 and the number @ 996 in the large array is 996
[U-CHILD] pid: 2 is running! the 4th fibonacci number is 3 and the number @ 995 in the large array is 995
[U-CHILD] pid: 2 is running! the 5th fibonacci number is 5 and the number @ 994 in the large array is 994
[U-CHILD] pid: 2 is running! the 6th fibonacci number is 8 and the number @ 993 in the large array is 993
[U-CHILD] pid: 2 is running! the 7th fibonacci number is 13 and the number @ 992 in the large array is 992
[U-CHILD] pid: 2 is running! the 8th fibonacci number is 21 and the number @ 991 in the large array is 991
[U-CHILD] pid: 2 is running! the 9th fibonacci number is 34 and the number @ 990 in the large array is 990
[U-CHILD] pid: 2 is running! the 10th fibonacci number is 55 and the number @ 989 in the large array is 989
[U-CHILD] pid: 2 is running! the 11th fibonacci number is 89 and the number @ 988 in the large array is 988
[U-CHILD] pid: 2 is running! the 12th fibonacci number is 144 and the number @ 987 in the large array is 987
[U-CHILD] pid: 2 is running! the 13th fibonacci number is 233 and the number @ 986 in the large array is 986
[U-CHILD] pid: 2 is running! the 14th fibonacci number is 377 and the number @ 985 in the large array is 985
[U-CHILD] pid: 2 is running! the 15th fibonacci number is 610 and the number @ 984 in the large array is 984
[U-CHILD] pid: 2 is running! the 16th fibonacci number is 987 and the number @ 983 in the large array is 983
[U-CHILD] pid: 2 is running! the 17th fibonacci number is 1597 and the number @ 982 in the large array is 982
[U-CHILD] pid: 2 is running! the 18th fibonacci number is 2584 and the number @ 981 in the large array is 981
[U-CHILD] pid: 2 is running! the 19th fibonacci number is 4181 and the number @ 980 in the large array is 980
[U-CHILD] pid: 2 is running! the 20th fibonacci number is 6765 and the number @ 979 in the large array is 979
[U-CHILD] pid: 2 is running! the 21th fibonacci number is 10946 and the number @ 978 in the large array is 978
[U-CHILD] pid: 2 is running! the 22th fibonacci number is 17711 and the number @ 977 in the large array is 977
[U-CHILD] pid: 2 is running! the 23th fibonacci number is 28657 and the number @ 976 in the large array is 976
[U-CHILD] pid: 2 is running! the 24th fibonacci number is 46368 and the number @ 975 in the large array is 975
[U-CHILD] pid: 2 is running! the 25th fibonacci number is 75025 and the number @ 974 in the large array is 974
[U-CHILD] pid: 2 is running! the 26th fibonacci number is 121393 and the number @ 973 in the large array is 973
[U-CHILD] pid: 2 is running! the 27th fibonacci number is 196418 and the number @ 972 in the large array is 972
[U-CHILD] pid: 2 is running! the 28th fibonacci number is 317811 and the number @ 971 in the large array is 971
[U-CHILD] pid: 2 is running! the 29th fibonacci number is 514229 and the number @ 970 in the large array is 970
[U-CHILD] pid: 2 is running! the 30th fibonacci number is 832040 and the number @ 969 in the large array is 969
[U-CHILD] pid: 2 is running! the 31th fibonacci number is 1346269 and the number @ 968 in the large array is 968
[U-CHILD] pid: 2 is running! the 32th fibonacci number is 2178309 and the number @ 967 in the large array is 967
[U-CHILD] pid: 2 is running! the 33th fibonacci number is 3524578 and the number @ 966 in the large array is 966
[U-CHILD] pid: 2 is running! the 34th fibonacci number is 5702887 and the number @ 965 in the large array is 965
[U-CHILD] pid: 2 is running! the 35th fibonacci number is 9227465 and the number @ 964 in the large array is 964
[U-CHILD] pid: 2 is running! the 36th fibonacci number is 14930352 and the number @ 963 in the large array is 963
[U-CHILD] pid: 2 is running! the 37th fibonacci number is 24157817 and the number @ 962 in the large array is 962
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[U-PARENT] pid: 1 is running! the 33th fibonacci number is 3524578 and the number @ 966 in the large array is 966
[U-PARENT] pid: 1 is running! the 34th fibonacci number is 5702887 and the number @ 965 in the large array is 965
[U-PARENT] pid: 1 is running! the 35th fibonacci number is 9227465 and the number @ 964 in the large array is 964
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U-CHILD] pid: 2 is running! the 38th fibonacci number is 39088169 and the number @ 961 in the large array is 961
[U-CHILD] pid: 2 is running! the 39th fibonacci number is 63245986 and the number @ 960 in the large array is 960
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[U-PARENT] pid: 1 is running! the 36th fibonacci number is 14930352 and the number @ 963 in the large array is 963
[U-PARENT] pid: 1 is running! the 37th fibonacci number is 24157817 and the number @ 962 in the large array is 962
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U-CHILD] pid: 2 is running! the 40th fibonacci number is 102334155 and the number @ 959 in the large array is 959
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U-CHILD] pid: 2 is running! the 41th fibonacci number is 165580141 and the number @ 958 in the large array is 958
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[U-PARENT] pid: 1 is running! the 38th fibonacci number is 39088169 and the number @ 961 in the large array is 961
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[U-PARENT] pid: 1 is running! the 39th fibonacci number is 63245986 and the number @ 960 in the large array is 960
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[U-CHILD] pid: 2 is running! the 42th fibonacci number is 267914296 and the number @ 957 in the large array is 957
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[S-MODE] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[S-MODE] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S-MODE] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S-MODE] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[U-PARENT] pid: 1 is running! the 40th fibonacci number is 102334155 and the number @ 959 in the large array is 959
```

## 思考题

1. 在第一个 `main` 函数中，缺少了哪种类型的 Page Fault？试运行第二个 `main` 函数，你能否找到这种类型的 Page Fault？为什么会发生这种类型的 Page Fault？
2. 为什么我们在 [拷贝内核态进程状态](#_9) 仅仅重新计算设置了 `sp` 与 `thread.sp`，但没有考虑同样发挥存储栈指针作用的 `thread.sscratch` 呢？那位于 `pt_regs` 中的 `sscratch` 又为什么没有被修改？
3. 在修改页表项的写权限时，我们需要使用 `sfence.vma` 指令来刷新 TLB。那如果我们不刷新 TLB，又可能会出现什么问题？
4. 对于 `Fork main #2` ，在运行时，`Message Sys3-Lab5` 位于内存的什么位置？是否在读取的时候产生了 Page Fault？请给出必要的截图以说明。

## 实验提交

请在学在浙大上提交以下两份文件：

- 实验报告（pdf）
- 软件部分全部代码压缩包（打包前 `make clean` 清除编译产物）

此外，在报告中需要给出 `getpid.c` 中各 `main` 函数的运行结果。如果不能全部实现，则可以只展示部分结果。
