# Lab3 RV64 虚拟内存管理实验报告

张子晨
3240106403

## 一、实验目的

本实验实现 RV64 Sv39 分页机制下的内核虚拟内存管理，完成内核从物理地址运行切换到高地址虚拟地址运行，并为内核不同段设置不同页表权限。

## 二、实现内容

### 1. 早期页表 `setup_vm`

早期页表只使用 Sv39 根页表，采用 1 GiB gigapage 映射。将物理地址 `0x80000000` 开始的 1 GiB 区域同时映射到：

- 等值映射：`VA = PA = 0x80000000`
- 高地址映射：`VA = PA + PA2VA_OFFSET = 0xffffffe000000000`

页表项设置为 `X | W | R | V | A | D`。其中 `A/D` 位手动置位，用于兼容未自动维护 A/D 位的模拟器。

### 2. 启动流程与 `relocate`

在 `head.S` 中，内核首先使用物理地址下可访问的启动栈，调用 `setup_vm` 构造早期页表。随后 `relocate` 完成：

- `ra += PA2VA_OFFSET`
- `sp += PA2VA_OFFSET`
- 写入 `satp = Sv39 | early_pgtbl_ppn`
- 通过 `ret` 跳转到高地址虚拟地址继续执行

之后调用 `mm_init` 初始化伙伴系统，再调用 `setup_vm_final` 切换到最终页表。

### 3. 最终页表 `setup_vm_final`

最终页表使用三级 Sv39 页表，只保留高地址 direct mapping，不再保留等值映射，也不映射 OpenSBI 区域。映射范围覆盖 128 MiB 物理内存，并按段设置权限：

- `.text`：`X | R`
- `.rodata`：`R`
- `.data/.bss/空闲内存`：`W | R`

实际运行时打印的映射如下：

```text
pgtbl = 0xffffffe000206000: map [0xffffffe000200000, 0xffffffe000202000) -> [0x80200000, 0x80202000), perm = 0xa
pgtbl = 0xffffffe000206000: map [0xffffffe000202000, 0xffffffe000203000) -> [0x80202000, 0x80203000), perm = 0x2
pgtbl = 0xffffffe000206000: map [0xffffffe000203000, 0xffffffe008000000) -> [0x80203000, 0x88000000), perm = 0x6
```

其中 `0xa = X|R`，`0x2 = R`，`0x6 = W|R`，符合实验要求。

### 4. `create_mapping`

`create_mapping` 以 4 KiB 页为粒度遍历映射区间。对于每个虚拟页：

1. 根据 Sv39 格式提取 `VPN[2]`、`VPN[1]`、`VPN[0]`。
2. 如果中间级页表项无效，则通过 `alloc_page` 分配新页表页并清零。
3. 中间级页表项只设置 `V` 位，叶子页表项设置 `PPN | perm | V | A | D`。
4. 页表项中保存的是物理页号，因此写入新页表地址时使用 `VA2PA` 转换。


## 四、思考题

### 1. 验证 `.text`、`.rodata` 段属性是否设置成功
直接make run,观察打印内容
![alt text](image.png)

- `.text` 映射权限为 `perm = 0xa`，即 `X | R`，可执行、可读、不可写。
- `.rodata` 映射权限为 `perm = 0x2`，即只读。
- 后续数据和空闲内存映射权限为 `perm = 0x6`，即 `W | R`，不可执行。


### 2. 为什么本实验需要等值映射，Linux 为什么不需要

1. 本实验原始实现中，若只是简单删除等值映射而不修改 `relocate`，在 `relocate` 中写入 `satp` 后，CPU 立即开启 Sv39 地址翻译。此时 PC 仍然位于物理地址附近，例如 `0x8020xxxx`。若 `early_pgtbl` 中没有等值映射，则写入 `satp` 后下一条指令取指时，会把当前低地址 PC 当作虚拟地址翻译，但页表中没有对应映射，因此发生 instruction page fault，内核无法继续执行到 `ret`，也就无法跳转到高地址虚拟地址。
现象是：内核没有进入
![alt text](<屏幕截图 2026-04-28 201721.png>)

2.Linux 不依赖简单的 PA == VA 等值映射。它在开启 MMU 前，会先把返回地址 ra 调整到内核虚拟地址，并把 stvec 设置为一个高地址虚拟地址标签。随后 Linux 写入 satp 使用 trampoline page table。写入 satp 后，当前 PC 仍是低地址，下一次取指可能触发异常；但异常入口 stvec 已经被设置到高地址虚拟地址，且 trampoline page table 能映射该虚拟地址，因此控制流可以进入高地址标签继续执行。之后 Linux 再切换到正式 early page table。

3. 我参考 Linux 的 trampoline 思路修改了本实验内核，使其不再依赖等值映射。核心做法是：早期页表只保留高地址映射；在写入 `satp` 前，把 `stvec` 设置为 `mapped_va` 标签的高地址虚拟地址。写入 `satp` 后，当前低地址 PC 无法继续取指，会触发 instruction page fault；由于此时 `stvec` 已经是高地址且早期页表映射了高地址 gigapage，处理器会跳转到高地址的 `mapped_va` 继续执行，随后执行 `ret` 跳转到已经加上 `PA2VA_OFFSET` 的返回地址。

具体代码改动如下。

`setup_vm` 中删除等值映射，只保留高地址映射：

```c
uint64_t entry = PA2PTE(PHY_START) | PTE_X | PTE_W | PTE_R | PTE_V | PTE_A | PTE_D;
early_pgtbl[VPN2(VM_START)] = entry;
```

`relocate` 中先修正 `ra`、`sp`，再把 `stvec` 指向高地址 trampoline 标签：

```asm
relocate:
    li t0, PA2VA_OFFSET
    add ra, ra, t0
    add sp, sp, t0

    la t1, mapped_va
    add t1, t1, t0
    csrw stvec, t1

    sfence.vma zero, zero

    la t0, early_pgtbl
    srli t0, t0, 12
    li t1, 8
    slli t1, t1, 60
    or t0, t0, t1
    csrw satp, t0

mapped_va:
    ret
```

通过运行验证。运行输出能够看到内核顺利进入高地址虚拟内存环境，完成 `buddy_init`、最终页表映射，并持续进行线程调度：

![alt text](image-1.png)

### 3. `kernel/lib/Makefile` 与 `-MMD` 的作用

本实验的 `kernel/lib/Makefile` 相比 Sys2 版本增加了 `.d` 依赖文件的管理：

- 根据源文件生成对应的 `.d` 文件列表。
- `clean` 时删除 `.d` 文件。
- 使用 `-include $(DEPS)` 读入依赖关系。

`kernel/Makefile` 中加入 `-MMD` 后，GCC 编译 `.c` 或 `.S` 文件时会自动生成头文件依赖文件。这样当某个头文件，例如 `private_kdefs.h`、`mm.h`、`vm.h` 被修改时，`make` 能够自动重新编译依赖它的目标文件，避免头文件变化但旧 `.o` 未更新导致调试结果异常。

### 4. `-fno-pie` 的影响

`-fno-pie` 用于禁止生成位置无关可执行相关代码。本实验内核是裸机内核，依赖链接脚本给出的固定虚拟地址，并在早期启动阶段手动完成物理地址到虚拟地址的切换，因此更适合生成普通 `EXEC` 类型目标。

当前开启 `-fno-pie` 时，检查结果如下：

```text
Type: EXEC (Executable file)
Entry point address: 0xffffffe000200000
There are no relocations in this file.
```

如果删除该选项，编译器可能为 `la` 等地址装载生成带 GOT/PIE 假设的访问序列，早期启动时这些地址尚未处于最终虚拟地址环境，可能导致取到错误地址，进而在设置栈、访问页表或跳转时失败。若要在删除 `-fno-pie` 后仍正常运行，需要避免依赖会通过 GOT 间接取地址的伪指令序列，在 `head.S` 中改用明确的 PC-relative 或显式常量计算方式获取符号地址，并确保启用分页前使用物理可访问地址、启用分页后使用高地址虚拟地址。

## 五、结论

本实验完成了 Sv39 早期页表和最终页表的建立，实现了从物理地址到高地址虚拟地址的切换，并为内核代码段、只读段和数据段设置了不同权限。QEMU 运行结果表明内核能够正常初始化内存、开启分页并持续进行线程调度。
