# XPart 拓展一：TLB 模块导读

这个拓展在基础 MMU 的页表遍历之上加入一个简化 TLB，用来缓存最近翻译过的虚拟页，减少重复访问同一页时的 page table walk。

## 实现位置

TLB 完全集成在 `src/project/submit/MMU.sv` 的 `MMUChannel` 中。因为 `MMU` 顶层分别实例化 `imem_mmu` 和 `dmem_mmu`，所以取指和访存各有一套独立的 TLB 状态。

## TLB 数据结构

关键定义：

```systemverilog
localparam int TLB_ENTRIES = 16;
localparam int TLB_INDEX_BITS = 4;

logic [TLB_ENTRIES-1:0] tlb_valid;
logic [26:0] tlb_vpn [TLB_ENTRIES];
logic [43:0] tlb_root_ppn [TLB_ENTRIES];
data_t tlb_pte [TLB_ENTRIES];
logic [1:0] tlb_level [TLB_ENTRIES];
```

含义：

- `tlb_valid`：当前 entry 是否有效。
- `tlb_vpn`：缓存的 Sv39 VPN，也就是 `va[38:12]`。
- `tlb_root_ppn`：缓存该翻译时的 `satp[43:0]`，防止不同地址空间误命中。
- `tlb_pte`：缓存叶子 PTE。
- `tlb_level`：记录叶子 PTE 位于第几级，支持 superpage 翻译。

当前采用直接映射，索引用低 4 位 VPN：

```systemverilog
wire [TLB_INDEX_BITS-1:0] tlb_index = selected_vpn[TLB_INDEX_BITS-1:0];
```

回填时使用 `req_vaddr[15:12]`，和 `selected_vpn[3:0]` 对应。

## 命中判断

命中条件：

```systemverilog
wire tlb_hit = sv39_enabled && !kernel_direct_access && canonical_addr &&
               tlb_valid[tlb_index] &&
               (tlb_vpn[tlb_index] == selected_vpn) &&
               (tlb_root_ppn[tlb_index] == satp[43:0]);
```

要点：

- 只有 Sv39 打开时使用 TLB。
- 内核高地址 direct map 不走 TLB，因为它是固定偏移转换。
- 非 canonical 地址直接 page fault，不允许 TLB 命中。
- `satp` 根 PPN 必须一致，避免进程切换后的旧翻译污染。

命中后仍然检查权限：

```systemverilog
wire tlb_perm_fault = permission_fault(tlb_pte[tlb_index], selected_write,
                                       selected_read, IS_INST, priv);
```

这保证 TLB 不绕过 X/R/W/U 权限检查。

## 状态机改动

TLB 改动主要发生在 `S_IDLE` 和 `S_WALK_RESP`。

### 命中路径

在 `S_IDLE` 中，如果 `tlb_hit`：

```text
S_IDLE -> S_ACCESS
```

不会进入 `S_WALK_REQ/S_WALK_RESP`。此时 `leaf_pte` 和 `leaf_level` 从 TLB 读出，`S_ACCESS` 直接使用 `translated_addr()` 得到最终物理地址。

如果命中但权限不满足：

```text
S_IDLE -> S_FAULT
```

异常类型仍由访问类型决定：取指、load 或 store page fault。

### 未命中和回填

未命中时仍走基础页表遍历：

```text
S_IDLE -> S_WALK_REQ -> S_WALK_RESP -> ...
```

在 `S_WALK_RESP` 收到合法叶子 PTE 后回填：

```systemverilog
tlb_valid[req_vaddr[15:12]] <= 1'b1;
tlb_vpn[req_vaddr[15:12]] <= req_vaddr[38:12];
tlb_root_ppn[req_vaddr[15:12]] <= satp[43:0];
tlb_pte[req_vaddr[15:12]] <= current_pte;
tlb_level[req_vaddr[15:12]] <= level;
```

## 刷新策略

TLB 在以下情况下清空：

```systemverilog
if (rst || switch_mode) begin
    tlb_valid <= '0;
end
```

`switch_mode` 来自 `AxiCore` 传入的 `cosim_switch_mode`。Core 中 `cosim_switch_mode = switch_mode | csr_satp_wb`，所以特权级切换和 `satp` 写回都会让 MMU 清掉旧 TLB。

## 和基础 MMU 的关系

TLB 没有改变 page fault 处理语义：

- TLB miss 时走原始 page table walk。
- TLB hit 时仍复用 `permission_fault()`。
- TLB 存的是 PTE 和 leaf level，不直接存最终物理页，方便复用 superpage 翻译逻辑。
- 地址空间切换时按 `satp` 和 flush 双保险隔离。

## 检验方法

最直接的功能测试是 shell 中的 `tlb` 命令。它反复访问同一页：

```c
static volatile uint64_t page[512] __attribute__((aligned(0x1000)));
```

重复触碰同一 hot page 后输出 checksum。如果 TLB 或 MMU 回填/命中路径有问题，通常会表现为 page fault 循环、访存错误或仿真异常。

先应用 mini_sbi 输入 patch：

```bash
git -C repo/sys-project apply ../../repo/patch/sys-project/1.patch
```

如果已经应用过，`git apply` 会提示无法重复应用，可以忽略或用验证脚本自动判断：

```bash
bash scripts/xpart_verify.sh tlb
```

手动验证命令：

```bash
make -C src/project clean
make -C src/project kernel T=SHELL
```

期望看到：

```text
[xpart-shell] read syscall + simple shell ready
$ tlb
tlb demo touched one hot page, checksum = 1161216
```

## 波形检查建议

如果需要向助教展示 TLB 的硬件证据，可以打开 Verilator 波形，观察 `MMUChannel` 内部信号：

- 第一次访问 hot page：`tlb_hit = 0`，状态经过 `S_WALK_REQ/S_WALK_RESP`。
- 后续访问同一页：`tlb_hit = 1`，状态从 `S_IDLE` 直接进入 `S_ACCESS`。
- `switch_mode` 或 `satp` 写回后：`tlb_valid` 被清零。

生成波形的命令仍是：

```bash
make -C src/project kernel T=SHELL
```

构建目录在 `src/project/build/verilate/`，波形文件由当前 testbench 配置生成。

## 常见问题

- 如果进程切换后随机访问错误，检查 `tlb_root_ppn` 是否参与命中判断，以及 `switch_mode` 是否包含 `csr_satp_wb`。
- 如果 store 访问错误没有触发异常，检查 `tlb_perm_fault` 是否仍调用 `permission_fault()`。
- 如果第一次访问可以、第二次访问挂住，优先看命中后 `leaf_pte/leaf_level` 是否正确锁存。
