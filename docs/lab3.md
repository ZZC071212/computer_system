<style>
code {
    font-family: "Consolas";
}
</style>

# 实验 3：RV64 虚拟内存管理

## 实验目的


* 理解虚拟内存的工作原理
* 实现物理地址到虚拟地址的切换
* 了解 RISC-V 的 SV39 分页模式
* 实现虚拟地址到物理地址的映射，并对不同的段进行相应的权限设置。

## 实验环境

* Linux OS in System II Lab5

## 背景知识

### 前言

在[系统二实验五](https://zju-sys.pages.zjusct.io/sys2/sys2-fa23/lab5/)中，我们赋予了 OS 对多个线程调度以及并发执行的能力，由于目前这些线程都是内核线程，因此他们可以共享运行空间，即运行不同线程对空间的修改是相互可见的。但是如果我们需要线程相互**隔离**，以及在多线程的情况下更加**高效**的使用内存，我们必须引入 `虚拟内存`这个概念。

虚拟内存可以为正在运行的进程提供独立的内存空间，制造一种每个进程的内存都是独立的假象。同时虚拟内存到物理内存的映射也包含了对内存的访问权限，方便 Kernel 完成权限检查。

在本次实验中，我们需要关注 OS 如何**开启虚拟地址**以及通过设置页表来实现**地址映射**和**权限控制**。

### Kernel 的虚拟内存布局

```
start_address             end_address
    0x0                  0x3fffffffff
     │                        │
┌────┘                  ┌─────┘
↓        256G           ↓
┌───────────────────────┬──────────┬────────────────┐
│      User Space       │    ...   │  Kernel Space  │
└───────────────────────┴──────────┴────────────────┘
                                   ↑      256G      ↑
                      ┌────────────┘                │ 
                      │                             │
              0xffffffc000000000           0xffffffffffffffff
                start_address                  end_address
```

通过上图我们可以看到 RV64 将 `0x0000004000000000` 以下的虚拟空间作为 `user space`。 将 `0xffffffc000000000` 及以上的虚拟空间作为 `kernel space`。由于我们还未引入用户态程序，目前我们只需要关注 `kernel space`。

本次实验使用的虚拟内存布局为 RISC-V Linux Kernel v5.16 前 Sv39 的内存布局，具体内容可以参考 [Virtual Memory Layout on RISC-V Linux](https://elixir.bootlin.com/linux/v5.15/source/Documentation/riscv/vm-layout.rst)。

在 `kernel space` 中有一段区域被称为 `direct mapping area`， 为了方便 kernel 可以高效率的访问 RAM， kernel 会预先把所有物理内存都映射至这一块区域 (PA + OFFSET == VA)， 这种映射也被称为 `linear mapping`。在 RISC-V Linux Kernel 中这一段区域为 `0xffffffe000000000 ~ 0xffffffff00000000`, 共 124 GB 。

### RISC-V 虚拟内存系统（Sv39 模式）

#### `satp` Register

SATP寄存器的全称为 Supervisor Address Translation and Protection Register。其内容如下所示：

```
 63      60 59                  44 43                                0
┌──────────┬──────────────────────┬───────────────────────────────────┐
│   MODE   │         ASID         │                PPN                │
└──────────┴──────────────────────┴───────────────────────────────────┘
```

其各个字段含义如下：

* MODE 字段的取值如下：
    ```
                            RV 64
    ┌─────────┬────────┬───────────────────────────────────────┐
    │  Value  │  Name  │  Description                          │
    ├─────────┼────────┼───────────────────────────────────────┤
    │    0    │ Bare   │ No translation or protection          │
    │  1 - 7  │ ---    │ Reserved for standard use             │
    │    8    │ Sv39   │ Page-based 39 bit virtual addressing  │ <-- 我们使用的 mode
    │    9    │ Sv48   │ Page-based 48 bit virtual addressing  │
    │    10   │ Sv57   │ Page-based 57 bit virtual addressing  │
    │    11   │ Sv64   │ Page-based 64 bit virtual addressing  │
    │ 12 - 13 │ ---    │ Reserved for standard use             │
    │ 14 - 15 │ ---    │ Reserved for standard use             │
    └─────────┴────────┴───────────────────────────────────────┘
    ```
* ASID (Address Space Identifier): 此次实验中直接置 0 即可。
* PPN (Physical Page Number): 顶级页表的物理页号。我们的物理页的大小为 4KB， PA >> 12 == PPN。

具体介绍请阅读 [RISC-V Privileged Spec 4.1.10](https://www.five-embeddev.com/riscv-isa-manual/latest/supervisor.html#sec:satp)

#### RISC-V Sv39 模式下的虚拟地址和物理地址

```
 38        30 29        21 20        12 11                           0
┌────────────┬────────────┬────────────┬──────────────────────────────┐
│   VPN[2]   │   VPN[1]   │   VPN[0]   │          page offset         │
└────────────┴────────────┴────────────┴──────────────────────────────┘
                        Sv39 virtual address
```

```
 55                30 29        21 20        12 11                           0
┌────────────────────┬────────────┬────────────┬──────────────────────────────┐
│       PPN[2]       │   PPN[1]   │   PPN[0]   │          page offset         │
└────────────────────┴────────────┴────────────┴──────────────────────────────┘
                            Sv39 physical address
```

Sv39 模式定义物理地址有 56 位，虚拟地址有 64 位。但是，虚拟地址的 64 位只有低 39 位有效（第 63-39 位全部等于第 38 位）。通过[虚拟内存布局图](#kernel-的虚拟内存布局)，我们可以发现 其 63-39 位为 0 时代表 user space address，为 1 时 代表 kernel space address。Sv39 支持三级页表结构，VPN[2-0](Virtual Page Number)分别代表每级页表的 `虚拟页号`，PPN[2-0](Physical Page Number)分别代表每级页表的 `物理页号`。物理地址和虚拟地址的低 12 位表示页内偏移（page offset）。

具体介绍请阅读 [RISC-V Privileged Spec 4.4.1](https://www.five-embeddev.com/riscv-isa-manual/latest/supervisor.html#sec:sv39)

#### RISC-V Sv39 模式页表项

```
 63      54 53        28 27        19 18        10 9   8 7 6 5 4 3 2 1 0
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

一些常用的位的含义如下：

* V: 有效位，当 V = 0, 访问该 PTE 会产生 Page Fault
* R: R = 1 该页可读
* W: W = 1 该页可写
* X: X = 1 该页可执行
* U, G, A, D, RSW 本次实验中设置为 0 即可

具体介绍请阅读 [RISC-V Privileged Spec 4.4.1](https://www.five-embeddev.com/riscv-isa-manual/latest/supervisor.html#sec:sv39)

#### RISC-V 地址转换

虚拟地址转化为物理地址流程图如下，具体描述可参考 [RISC-V Privileged Spec 4.3.2](https://www.five-embeddev.com/riscv-isa-manual/latest/supervisor.html#sv32algorithm) :

```
                                Virtual Address                                     Physical Address

                          9             9            9              12          55        12 11       0
   ┌────────────────┬────────────┬────────────┬─────────────┬────────────────┐ ┌────────────┬──────────┐
   │                │   VPN[2]   │   VPN[1]   │   VPN[0]    │     OFFSET     │ │     PPN    │  OFFSET  │
   └────────────────┴────┬───────┴─────┬──────┴──────┬──────┴───────┬────────┘ └────────────┴──────────┘
                         │             │             │              │                 ▲          ▲
                         │             │             │              │                 │          │
                         │             │             │              │                 │          │
┌────────────────────────┘             │             │              │                 │          │
│                                      │             │              │                 │          │
│                                      │             │              └─────────────────┼──────────┘
│    ┌─────────────────┐               │             │                                │
│511 │                 │  ┌────────────┘             │                                │
│    │                 │  │                          │                                │
│    │                 │  │     ┌─────────────────┐  │                                │
│    │                 │  │ 511 │                 │  │                                │
│    │                 │  │     │                 │  │                                │
│    │                 │  │     │                 │  │     ┌─────────────────┐        │
│    │   44       10   │  │     │                 │  │ 511 │                 │        │
│    ├────────┬────────┤  │     │                 │  │     │                 │        │
└───►│   PPN  │  flags │  │     │                 │  │     │                 │        │
     ├────┬───┴────────┤  │     │   44       10   │  │     │                 │        │
     │    │            │  │     ├────────┬────────┤  │     │                 │        │
     │    │            │  └────►│   PPN  │  flags │  │     │                 │        │
     │    │            │        ├────┬───┴────────┤  │     │   44       10   │        │
     │    │            │        │    │            │  │     ├────────┬────────┤        │
   1 │    │            │        │    │            │  └────►│   PPN  │  flags │        │
     │    │            │        │    │            │        ├────┬───┴────────┤        │
   0 │    │            │        │    │            │        │    │            │        │
     └────┼────────────┘      1 │    │            │        │    │            │        │
     ▲    │                     │    │            │        │    └────────────┼────────┘
     │    │                   0 │    │            │        │                 │
     │    └────────────────────►└────┼────────────┘      1 │                 │
     │                               │                     │                 │
 ┌───┴────┐                          │                   0 │                 │
 │  satp  │                          └────────────────────►└─────────────────┘
 └────────┘
```

## 实验步骤

### 准备工程

* 此次实验基于[系统二实验五](https://zju-sys.pages.zjusct.io/sys2/sys2-fa23/lab5/)中同学所实现的代码进行。
* 需要修改 `defs.h`, 在 `defs.h` `添加` 如下内容：
    ```c
    #define OPENSBI_SIZE (0x200000)
    
    #define VM_START (0xffffffe000000000)
    #define VM_END   (0xffffffff00000000)
    #define VM_SIZE  (VM_END - VM_START)
    
    #define PA2VA_OFFSET (VM_START - PHY_START)
    ```
* 从 [`repo`](https://git.zju.edu.cn/zju-sys/sys3/sys3-sp24) 同步以下文件：
    ```
    src/lab3
    ├── arch
    │   └── riscv
    │       ├── include
    │       │   └── vm.h
    │       └── kernel
    │           ├── vm.c
    │           └── vmlinux.lds
    └── Makefile
    ```
    链接脚本 `vmlinux.lds` 中的 `ramv` 代表 `LMA (Virtual Memory Address)`，即虚拟地址；`ram` 则代表 `LMA (Load Memory Address)`, 即我们 OS image 被 load 的地址，可以理解为物理地址。使用以上的 vmlinux.lds 进行编译之后，得到的 `System.map` 以及 `vmlinux` 采用的都是虚拟地址，方便之后 Debug。
* 本实验中我们需要使用刷新缓存的指令扩展，并自动在编译项目前执行 clean 任务来防止对头文件的修改无法触发编译任务。根目录下 Makefile 已经做了相应的修改，同学们可以直接使用。

### 开启虚拟内存映射。

在 RISC-V 中开启虚拟地址被分为了两步：`setup_vm` 以及 `setup_vm_final`。第一步通过调用 `setup_vm` 建立临时页表，第二步通过调用 `setup_vm_final` 建立正式页表。下面将介绍相关的具体实现。

#### `setup_vm` 的实现

将 0x80000000 开始的 1GB 区域进行两次映射，其中一次是等值映射 (PA == VA) ，另一次是将其映射至高地址 (PA + PV2VA\_OFFSET == VA)。如下图所示：

```
Physical Address
┌────────────────────┬─────────┬────────┬─┐
│                    │ OpenSBI │ Kernel │ │
└────────────────────┴─────────┴────────┴─┘
                     ↑
                0x80000000
                     ├───────────────────────────────────────────────────┐
                     │                                                   │
Virtual Address      ↓                                                   ↓
┌────────────────────┬─────────┬────────┬────────────────────────────────┬─────────┬────────┬─┐
│                    │ OpenSBI │ Kernel │                                │ OpenSBI │ Kernel │ │
└────────────────────┴─────────┴────────┴────────────────────────────────┴─────────┴────────┴─┘
                     ↑                                                   ↑
                0x80000000                                       0xffffffe000000000
```

在这个函数中，你需要填写页表 `early_pgtbl` 中的对应项，以保证虚拟地址0xffffffe000000000能够成功地映射到物理地址0x80000000上。

```c
// arch/riscv/kernel/vm.c

/* early_pgtbl: 用于 setup_vm 进行 1GB 的 映射。 */
unsigned long early_pgtbl[512] __attribute__((__aligned__(0x1000)));

void setup_vm(void)
{
    /*
    1. 由于是进行 1GB 的映射 这里不需要使用多级页表
    2. 将 va 的 64bit 作为如下划分： | high bit | 9 bit | 30 bit |
        high bit 可以忽略
        中间9 bit 作为 early_pgtbl 的 index
        低 30 bit 作为 页内偏移 这里注意到 30 = 9 + 9 + 12， 即我们只使用根页表， 根页表的每个 entry 都对应 1GB 的区域。
    3. Page Table Entry 的权限 V | R | W | X 位设置为 1
    */
}
```

#### 修改 `head.S`

完成4.2.1中的映射之后，通过 `relocate` 函数，完成对 `satp` 的设置，以及跳转到对应的虚拟地址。

```asm
# head.S

_start:

    call setup_vm
    call relocate

    ...

    j start_kernel

relocate:
    # set ra = ra + PA2VA_OFFSET
    # set sp = sp + PA2VA_OFFSET (If you have set the sp before)

    ###################### 
    #   YOUR CODE HERE   #
    ######################

    # set satp with early_pgtbl

    ###################### 
    #   YOUR CODE HERE   #
    ######################

    # flush tlb
    sfence.vma zero, zero

    # flush icache
    fence.i

    ret

    .section .bss.stack
    .globl boot_stack
boot_stack:
    ...
```

至此我们已经完成了虚拟地址的开启，之后我们运行的代码也都将在虚拟地址上运行。

!!! tip "提示"
    1. `sfence.vma` 指令用于刷新 TLB，`fence.i` 指令用于刷新 icache
    2. 因为 GDB 加载的符号均为虚拟地址，所以在设置 `satp` 前，我们只可以使用**物理地址**来打断点。你的代码将被加载到物理地址 `PHY_START + OPENSBI_SIZE` 处 (`0x80200000`)，调试时可以在这里打断点。设置 `satp` 之后，才可以使用虚拟地址打断点，同时之前设置的物理地址断点也会失效。

#### `setup_vm_final` 的实现

* 由于 `setup_vm_final` 中需要申请页面的接口，应该在其之前完成内存管理初始化需要修改 `mm.c` 中的代码，`mm.c` 中初始化的函数接收的起始结束地址需要调整为虚拟地址。

* 对 所有物理内存 (128M) 进行映射，并设置正确的权限。
    ```
    Physical Address
          PHY_START                           PHY_END
              ↓                                  ↓
    ┌────────┬─────────┬────────┬───────────────┐
    │        │ OpenSBI │ Kernel │               │
    └────────┴─────────┴────────┴───────────────┘
              ^                                  ^
        0x80000000                              └───────────────────────────────────────────────────┐
              └───────────────────────────────────────────────────┐                                  │
                                                                  │                                  │
                                                              VM_START                              │
    Virtual Address                                              ↓                                  ↓
    ┌────────────────────────────────────────────────────────────┬─────────┬────────┬───────────────┐
    │                                                            │ OpenSBI │ Kernel │               │
    └────────────────────────────────────────────────────────────┴─────────┴────────┴───────────────┘
                                                                  ^
                                                          0xffffffe000000000
    ```
* 不再需要进行等值映射。
* 不再需要将 OpenSBI 的地址映射至高地址，因为 OpenSBI 运行在 M 态， 直接使用的物理地址。
* 采用三级页表映射。
* 在 head.S 中 适当的位置调用 `setup_vm_final`。
    ```c
    void setup_vm_final(void) {
        memset(swapper_pg_dir, 0x0, PGSIZE);
    
        // No OpenSBI mapping required
    
        // mapping kernel text X|-|R|V
        create_mapping(...);
    
        // mapping kernel rodata -|-|R|V
        create_mapping(...);
        
        // mapping other memory -|W|R|V
        create_mapping(...);
        
        // set satp with swapper_pg_dir
    
        YOUR CODE HERE
    
        // flush TLB
        asm volatile("sfence.vma zero, zero");
        return;
    }
    
    /* 创建多级页表映射关系 */
    void create_mapping(uint64 *pgtbl, uint64 va, uint64 pa, uint64 sz, uint64 perm) {
        /*
        pgtbl 为根页表的基地址
        va, pa 为需要映射的虚拟地址、物理地址
        sz 为映射的大小
        perm 为映射的读写权限
    
        将给定的一段虚拟内存映射到物理内存上
        物理内存需要分页
        创建多级页表的时候可以使用 kalloc() 来获取一页作为页表目录
        可以使用 V bit 来判断页表项是否存在
        */
    }
    ```

### 编译及测试

由于加入了一些新的文件，可能需要修改一些 Makefile，请同学自己尝试修改，使项目可以编译并运行。输出示例如下：
```bash
OpenSBI v0.9
... 
Boot HART MIDELEG         : 0x0000000000000222
Boot HART MEDELEG         : 0x000000000000b109
...mm_init done!
...proc_init done!
2024 ZJU Computer System III
[S] SET [PID = 3 PRIORITY = 5 COUNTER = 5]
[S] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[PID = 1] is running. auto_inc_local_var = 1. Thread space begin at ffffffe007fbe000
[S] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[PID = 2] is running. auto_inc_local_var = 1. Thread space begin at ffffffe007fbd000
...
[PID = 2] is running. auto_inc_local_var = 4. Thread space begin at ffffffe007fbd000
[S] switch to [PID = 3, COUNTER = 5, PRIORITY = 5]
[PID = 3] is running. auto_inc_local_var = 1. Thread space begin at ffffffe007fbc000
...
[PID = 3] is running. auto_inc_local_var = 5. Thread space begin at ffffffe007fbc000
[S] SET [PID = 3 PRIORITY = 5 COUNTER = 5]
[S] SET [PID = 2 PRIORITY = 4 COUNTER = 4]
[S] SET [PID = 1 PRIORITY = 1 COUNTER = 1]
[S] switch to [PID = 1, COUNTER = 1, PRIORITY = 1]
[PID = 1] is running. auto_inc_local_var = 2. Thread space begin at ffffffe007fbe000
[S] switch to [PID = 2, COUNTER = 4, PRIORITY = 4]
[PID = 2] is running. auto_inc_local_var = 5. Thread space begin at ffffffe007fbd000
...
```

## 思考题

1. 验证 `.text`, `.rodata` 段的属性是否成功设置，给出截图。
2. 为什么我们在 `setup_vm` 中需要做等值映射？在 Linux 中，是不需要做等值映射的。请探索一下不在 `setup_vm` 中做等值映射的方法。
3. 什么是 Position Independent Executables (PIE)？在这次实验给出的根目录 Makefile 中，删除了 `-fno-pie` 编译选项，对生成的 `vmlinux` 有什么影响？

## 作业提交

同学需要提交实验报告以及整个工程代码。在提交前请使用 `make clean` 清除所有构建产物。
