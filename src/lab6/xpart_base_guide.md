# XPart 基础部分代码导读

这份导读对应 XPart 必做基础部分：在现有 CPU 上接入 Sv39 MMU，支持内核高地址运行、用户态页表、缺页异常、用户程序调度和 lab5 风格内核启动。

## 目标范围

基础部分完成的是一条完整的软硬件执行链：

1. Core 发出的取指/访存请求进入 MMU。
2. MMU 根据 `satp`、特权级和虚拟地址做 Sv39 地址翻译。
3. 翻译失败或权限不满足时抛出 page fault。
4. CSR/异常通路把异常交给内核 trap。
5. 内核按 VMA 懒分配用户页，补齐页表后返回用户态继续执行。
6. 用户程序能在调度器中持续运行。

## 硬件侧模块

### `src/project/submit/MMU.sv`

这是基础部分的核心硬件模块。顶层 `MMU` 分成两个 `MMUChannel`：

- `imem_mmu`：处理取指请求，异常类型为 instruction page fault。
- `dmem_mmu`：处理 load/store 请求，异常类型为 load page fault 或 store page fault。

每个 `MMUChannel` 都在 Core 和真实内存总线之间工作。它的状态机包括：

- `S_IDLE`：等待 Core 请求，判断是否直通、缺页、TLB 命中或页表遍历。
- `S_DIRECT`：未开启 Sv39、M 态访问、或 S 态访问内核 direct map 时直接访问物理地址。
- `S_WALK_REQ`：向内存发起 PTE 读取请求。
- `S_WALK_RESP`：接收 PTE，判断无效项、叶子项、权限和 superpage 对齐。
- `S_ACCESS`：拿到最终物理地址后，把 Core 请求转发给内存。
- `S_FAULT`：产生 `except_mmu`，等待特权级切换后回到空闲。

基础地址翻译相关的关键函数和信号：

- `sv39_enabled`：`satp.MODE == 8` 且当前不在 M 态时启用翻译。
- `canonical_addr`：检查 Sv39 虚拟地址高位符号扩展是否合法。
- `kernel_direct_access`：S 态访问 `VM_START..VM_START+PHY_SIZE` 时直接转换为物理地址。
- `pte_table_addr()`：根据根 PPN、VPN 和 level 计算当前 PTE 物理地址。
- `pte_is_invalid()` / `pte_is_leaf()`：判断 PTE 合法性和是否为叶子项。
- `permission_fault()`：检查 X/R/W/U 权限。
- `translated_addr()`：支持 4 KiB、2 MiB、1 GiB 叶子页翻译。
- `except_mmu`：把 `epc`、`ecause`、`etval` 传给 CSR 异常通路。

### `src/project/submit/Core.sv`

Core 为 XPart 增加了 MMU/CSR 需要的接口：

- 输入 `except_mmu`：接收 MMU page fault。
- 输出 `satp`、`output_priv`：提供当前页表根和特权级给 MMU。
- 输出 `pc_if`、`pc_mem`：分别给取指异常和访存异常作为 EPC。
- 输出 `cosim_switch_mode`：特权级切换或 `satp` 写回时通知 MMU 刷新状态。

同时 Core 对流水线做了几处配合：

- `csr_satp_wb` 检测 `satp` 写回，触发 PC 重新取指和流水线清空。
- `switch_mode` 或 `csr_satp_wb` 时清空 IF/ID/EX/MEM 相关状态，避免旧地址空间中的请求继续提交。
- IF/MEM 请求通过简单 FSM 串行化，保证当前无 cache 情况下不会把 MMU 通道打乱。
- `commit_exception` 控制异常提交时的写回屏蔽。

### `src/project/submit/CSRModule.sv`

CSR 模块负责 XPart 的异常、特权级和页表根寄存器：

- 新增/维护 `satp_reg`，作为 MMU 页表根输入。
- 接收 `except_mmu`，与流水线异常合并为最终异常。
- 维护 `priv`，支持 trap 后进入 S/M 态，`sret/mret` 后返回原特权级。
- 输出 `switch_mode` 和 `pc_csr`，用于 Core 重定向到 `stvec/mtvec/sepc/mepc`。
- `sret` 返回精确 `sepc`，不做额外 `-4` 补偿。

### `src/project/submit/IDExceptExamine.sv` 和 `ExceptReg.sv`

这两个模块负责 ID 阶段的指令合法性和异常流水：

- 识别 `ecall`、`ebreak`、非法 CSR/system 指令。
- 产生 `ExceptPack`，并通过 `ExceptReg` 流到后续阶段。
- 与 MMU 异常一起进入 CSR 提交通路。

## 内核侧模块

### `src/project/kernel/Makefile`

基础构建入口加入用户程序：

- `T ?= PFH1` 指定默认用户程序。
- `CPPFLAGS += -DUSER_MAIN=$(T)` 把目标用户程序传给内核和用户 app。
- 先构建 `lib` 和 `user`，再把 `user/uapp.o` 链接进 `vmlinux`。

### `src/project/kernel/arch/riscv/kernel/head.S`

启动流程：

1. 设置启动栈。
2. 调用 `setup_vm()` 建立 early page table。
3. `relocate` 写 `satp`，通过高地址 trampoline 进入虚拟地址空间。
4. 调用 `setup_vm_final()` 建立最终内核页表。
5. 设置 `stvec`、定时器，进入 `start_kernel`。

### `src/project/kernel/arch/riscv/kernel/vm.c`

页表相关实现：

- `setup_vm()`：建立 early 1 GiB 高地址映射。
- `setup_vm_final()`：建立最终 `swapper_pg_dir`，写入 `satp` 并 `sfence.vma`。
- `create_mapping()`：创建 Sv39 三级页表，按 4 KiB 页建立映射。
- `walk_page_table()`：返回某虚拟地址对应的叶子 PTE 指针，用于 page fault 和 COW。

### `src/project/kernel/arch/riscv/include/vm.h`

新增 PTE flag 和地址转换宏：

- `PTE_V/R/W/X/U/A/D/S`
- `PTE_FLAGS_MASK`
- `PTE2PA()` / `PA2PTE()`
- `walk_page_table()` 声明

### `src/project/kernel/arch/riscv/kernel/mm.c`

物理页分配器适配高地址内核运行：

- `kernel_symbol_va()` 把链接时物理符号转换为高地址 direct map。
- `buddy_init()` 从 `_ekernel` 后初始化 bitmap/ref count。
- `ref_page()` / `deref_page()` 为 fork/COW 提供引用计数。

### `src/project/kernel/arch/riscv/kernel/proc.c`

进程和用户地址空间：

- `setup_user_pagetable()` 复制内核页表作为每个用户任务的根页表。
- `setup_user_mm()` 建立用户程序段和用户栈 VMA。
- `do_mmap()` / `find_vma()` 管理合法虚拟地址范围。
- `task_init()` 根据 `USER_MAIN` 创建用户任务。
- `schedule()` / `switch_to()` 完成调度。
- `do_fork()` 和 COW 相关逻辑为后续 shell 的 `fork` 命令提供基础。

### `src/project/kernel/arch/riscv/kernel/trap.c`

trap 处理：

- 定时器中断进入 `do_timer()`。
- 用户 ecall 分发系统调用。
- page fault 进入 `do_page_fault()`：
  - 查找 VMA。
  - 检查访问权限。
  - 若是 COW 写 fault，复制物理页并恢复写权限。
  - 若是首次访问用户程序/栈，分配新页并建立映射。
  - `sfence.vma` 后返回，用户态重新执行触发 fault 的指令。

### 用户程序与基础库

相关文件：

- `src/project/kernel/user/src/main.c`：PFH1/PFH2/FORK 系列用户程序。
- `src/project/kernel/user/src/head.S`：用户程序入口。
- `src/project/kernel/user/uapp.S` / `uapp.lds`：把用户二进制嵌入内核。
- `src/project/kernel/lib/*` 和 `src/project/kernel/include/*`：给内核与用户 app 共用的简化 libc。

## 基础执行流

```text
head.S
  -> setup_vm()
  -> relocate, write satp
  -> setup_vm_final()
  -> start_kernel()
  -> buddy_init()
  -> task_init()
  -> schedule()
  -> __switch_to()
  -> user app at USER_START
  -> page fault
  -> MMU except_mmu
  -> CSR trap to _traps
  -> trap_handler()
  -> do_page_fault()
  -> sret, retry user instruction
```

## 检验方法

建议先保证子模块在 `sys3-xpart`：

```bash
git submodule update --init --recursive
git -C repo/sys-project checkout sys3-xpart
```

基础目标不依赖 shell 输入 patch，可以直接跑：

```bash
make -C src/project clean
make -C src/project kernel T=PFH1
```

看到类似输出即可说明基础链路跑通：

```text
...buddy_init done!
...task_init done!
switch to [PID = ...
[U] [PID = ..., sp = ...]
```

也可以用验证脚本：

```bash
bash scripts/xpart_verify.sh base
```

如果要测试会频繁访问用户数据页的 PFH2：

```bash
make -C src/project clean
make -C src/project kernel T=PFH2
```

## 常见问题

- 运行末尾出现 `[CJ] no simulation time` 通常是仿真时间到达上限，不等于构建失败；以 `make` 返回码和前面的用户态输出为准。
- 如果出现 `kernel out of memory`，检查 `src/project/kernel/arch/riscv/include/private_kdefs.h` 中 `PHY_SIZE`。
- 如果用户态完全没有输出，优先检查 `satp` 写入、`pc_csr` 重定向、`switch_mode/csr_satp_wb` 清流水线。
- 如果 page fault 后不断重复，优先检查 `trap.c` 的 `stval` 对齐、`create_mapping()` 权限和 `sfence.vma`。
