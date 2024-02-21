# 实验 6：RV64 缺页异常处理

## 实验目的
* 通过 `vm_area_struct` 数据结构实现对进程**多区域**虚拟内存的管理。
* 在 [Lab5](../lab5) 实现用户态程序的基础上，添加缺页异常处理 **Page Fault Handler**。

## 实验环境 

* 与前一实验一致

## 背景知识

### vm_area_struct 介绍

在 Linux 系统中，`vm_area_struct` 是虚拟内存管理的基本单元，保存了有关连续虚拟内存区域（简称 `VMA`）的信息。Linux 具体某一进程的虚拟内存区域映射关系可以通过 [procfs](https://man7.org/linux/man-pages/man5/procfs.5.html) 读取 `/proc/pid/maps` 的内容来获取:

比如，如下一个常规的 `bash` 进程，假设它的进程号为 `7884` ，则通过输入如下命令，就可以查看该进程具体的虚拟地址内存映射情况(部分信息已省略)。

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
* `vm_start`:（第 1 列）指的是该段虚拟内存区域的开始地址
* `vm_end`:（第 2 列）指的是该段虚拟内存区域的结束地址
* `vm_flags`:（第 3 列）该 `vm_area` 的一组权限（rwx）标志，`vm_flags` 的具体取值定义可参考linux源代码的 [linux/mm.h](https://elixir.bootlin.com/linux/v5.15/source/include/linux/mm.h#L265)
* `vm_pgoff`:（第 4 列）虚拟内存映射区域在文件内的偏移量
* `vm_file`:（第 5/6/7 列）分别表示：映射文件所属设备号/指向关联文件结构的指针（如果有的话，一般为文件系统的 inode）/文件名

!!! note "关于虚拟内存区域"
    注意这里记录的 `vm_start` 和 `vm_end` 都是用户态的虚拟地址，并且内核并不会将除了用户程序会用到的内存区域以外的部分添加成为 VMA。

我们注意到，一段内存中的内容可能是由磁盘中的文件映射的。如果这样的内存的 VMA 产生了缺页异常，说明文件中对应的页不在操作系统的 buffer pool 中，或者是由于 buffer pool 的调度策略被换出到磁盘上了。这时候操作系统会用驱动读取硬盘上的内容，放入 buffer pool，然后修改当前 task 的页表来让其能够用原来的地址访问文件内容。而这一切对用户程序来说是完全透明的，除了访问延迟。除了跟文件建立联系以外，VMA 还可能是一块匿名（anonymous）的区域。例如被标成 `[stack]` 的这一块区域，并没有对应的文件。

其它保存在 `vm_area_struct` 中的信息还有：
* `vm_ops`: 该`vm_area`中的一组工作函数
* `vm_next/vm_prev`: 同一进程的所有虚拟内存区域由**链表结构**链接起来，这是分别指向前后两个 `vm_area_struct` 结构体的指针

可以发现，原本的 Linux 使用链表对一个 task 内的 VMA 进行管理。但是由于如今一个程序可能体量非常巨大，所以现在的 Linux 已经用虚拟地址为索引来建立红黑树了。

### 缺页异常 Page Fault

在一个启用了虚拟内存的系统上，若正在运行的程序访问当前未由内存管理单元（MMU）映射到虚拟内存的页面，或访问权限不足，则会由计算机硬件引发的缺页异常（Page Fault）。

处理缺页异常通常是操作系统内核的一部分。当处理缺页异常时，操作系统将尝试使所需页面在物理内存中的位置变得可访问（建立新的映射关系到虚拟内存）。而如果在非法访问内存的情况下，发现触发 `Page Fault` 的虚拟内存地址（Bad Address）不在当前进程 `vm_area_struct` 链表所定义的允许访问的虚拟内存地址范围内，或访问位置的权限条件不满足时，缺页异常处理将终止该程序的继续运行。 

#### Demand Paging

Demand Paging 遵循的原则是，只有在执行进程需要时，才应将页面放入内存中。这样做的好处是，仅加载执行进程所需的页面，从而节省内存空间。例如，若一个页面从未被访问过，那么它就不需要被放入内存中。

#### RISC-V Page Faults

在 RISC-V 中，当系统运行发生异常时，可通过解析 `scause` 寄存器的值，识别如下三种不同的 Page Fault：
| Interrupt | Exception Code | Description |
| --- | --- | --- |
| 0 | 12 | Instruction Page Fault |
| 0 | 13 | Load Page Fault |
| 0 | 15 | Store/AMO Page Fault |

#### 处理 Page Fault 的方式

处理缺页异常时可能所需的信息如下：
* 触发 Page Fault 时访问的虚拟内存地址。当触发 Page Fault 时，`stval` 寄存器被被硬件自动设置为该出错的VA地址
* 导致 Page Fault 的类型，保存在 `scause` 寄存器中
    * Exception Code = 12: page fault caused by an instruction fetch 
    * Exception Code = 13: page fault caused by a read  
    * Exception Code = 15: page fault caused by a write 
* 发生 Page Fault 时的指令执行位置，保存在 `sepc` 中
* 当前进程合法的 VMA 映射关系，保存在 `vm_area_struct` 链表中
* 发生异常的虚拟地址对应的 PTE (page table entry) 中记录的信息

总的说来，处理缺页异常需要进行以下步骤：
* 捕获异常
* 寻找当前 task 中导致产生了异常的地址对应的 VMA
* 判断产生异常的原因
  * 如果是匿名区域，那么开辟一页内存，然后把这一页映射到产生异常的 task 的页表中。如果不是，那么首先将硬盘中的内容读入 buffer pool，将 buffer pool 中这段内存映射给 task。
* 返回到产生了该缺页异常的那条指令，并继续执行程序

## 实验步骤

### 准备工作

* 此次实验基于 Lab5 同学所实现的代码进行。
* 从 repo 同步以下文件夹: user 并按照以下步骤将这些文件正确放置。
    ```
    lab6
    └── user
        └── getpid.c
    ```
* 在 `user/getpid.c` 中我们设置了两个 `main` 函数，其中注释的部分是思考题所需要的内容。

### 实现虚拟内存管理功能

修改 `proc.h`，添加如下内容：

```c
/* vm_area_struct vm_flags */
#define VM_READ		0x00000001
#define VM_WRITE	0x00000002
#define VM_EXEC		0x00000004

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

每一个 vm_area_struct 都对应于进程地址空间的唯一区间。注意我们这里的 `vm_flag` 标志位和 PTE 的标志位并没有按 bit 进行对应，请同学们仔细对照 bit 的位置，以免出现问题。

此外，为了支持 `Demand Paging`，我们需要支持对 `vm_area_struct` 的添加，查找。
* `find_vma` 函数：实现对 `vm_area_struct` 的查找
	* 根据传入的地址 `addr`，遍历链表 `mm` 包含的 vma 链表，找到该地址所在的 `vm_area_struct `
	* 如果链表中所有的 `vm_area_struct` 都不包含该地址，则返回 `NULL`
```c
/*
* @mm          : current thread's mm_struct
* @address     : the va to look up
*
* @return      : the VMA if found or NULL if not found
*/
struct vm_area_struct *find_vma(struct mm_struct *mm, uint64 addr);
```
* `do_mmap` 函数：实现 `vm_area_struct` 的添加
	* 新建 `vm_area_struct` 结构体，根据传入的参数对结构体赋值，并添加到 `mm` 指向的 vma 链表中
	* 需要检查传入的参数 `[addr, addr + length)` 是否与 vma 链表中已有的 `vm_area_struct` 重叠，如果存在重叠，则需要调用 `get_unmapped_area` 函数寻找一个其它合适的位置进行映射
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
* `get_unmapped_area` 函数：用于解决 `do_mmap` 中 `addr` 与已有 vma 重叠的情况
	* 我们采用最简单的暴力搜索方法来寻找未映射的长度为 `length`（按页对齐）的虚拟地址区域
	* 从 `0` 地址开始向上以 `PGSIZE` 为单位遍历，直到遍历到连续 `length` 长度内均无已有映射的地址区域，将该区域的首地址返回
```c
uint64 get_unmapped_area(struct mm_struct *mm, uint64 length);
```

### 修改 task_init 函数

Linux 在 Page Fault Handler 中需要考虑多种情况。我们的实验经过简化，只需要根据 `vm_area_struct` 中的 `vm_flags` 来确定当前发生了什么样的错误，并且需要如何处理。在初始化一个 task 时我们既不分配内存，又不更改页表项来建立映射。回退到用户态进行程序执行的时候就会因为没有映射而发生 Page Fault，进入我们的 Page Fault Handler 后，我们再分配空间（按需要拷贝内容）进行映射。

根据这种思想，在调用 `do_mmap` 映射页面时，我们不直接对页表进行修改，只是在该进程所属的 `mm->mmap` 链表上添加一个 `vma` 记录。之后，当我们真正访问这个页面时，会触发缺页异常。在缺页异常处理函数中，我们需要根据缺页的地址，找到该地址对应的 `vma`，根据 `vma` 中的信息对页表进行映射。

因此，修改 `task_init` 函数代码，更改为 `Demand Paging`
  * 删除之前实验中对 `uapp`、栈进行映射的代码
  * 调用 `do_mmap` 函数，为进程的 vma 链表添加新的 `vm_area_struct` 结构，从而建立用户进程的虚拟地址空间信息，包括两个区域：
      * 代码区域, 该区域从虚拟地址 `USER_START` 开始，大小为 `uapp_end - uapp_start`， 权限为 `VM_READ | VM_WRITE | VM_EXEC`
      * 用户栈，范围为 `[USER_END - PGSIZE, USER_END)` ，权限为 `VM_READ | VM_WRITE`

在完成上述修改之后，如果运行代码我们可以截获一个 Page Fault，如下：
```bash 
// Instruction Page Fault
Page fault at 0000000000000000, badaddr is 0000000000000000, scause: 000000000000000c
```

### 实现 Page Fault Handler

在中断异常处理逻辑中实现 Page Fault 的检测与处理：
* 修改 `trap.c`，添加捕获 Page Fault 的逻辑。
* 当捕获了 `Page Fault` 之后，需要实现缺页异常的处理函数 `do_page_fault`。如上面展示的 Instruction Page Fault，对这个异常需要同学们新分配一个页，并拷贝 `uapp` 的对应内容到新分配的页内。
* 其他类型的缺页异常也可以参考如上的处理方式。
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

### 编译及测试

对于第一个 `main` 函数，输出示例如下：
```bash
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

## 思考题

1. 对于第一个 `main` 函数，以 PID 为 1 的进程为例，请你结合 `objdump` 获得的代码，分析 Page Fault 发生的原因。
2. 在第一个 `main` 函数中，缺少了哪种类型的 Page Fault？试运行第二个 `main` 函数，你能否找到这种类型的 Page Fault？为什么会发生这种类型的 Page Fault？

## 作业提交

同学们需要提交实验报告以及整个工程代码。在提交前请使用 `make clean` 清除所有构建产物。
