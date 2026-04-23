# Lab2 Cache 实验报告

## 一、实验目的

本实验的目标是在已有五级流水 CPU 上接入 I-Cache 和 D-Cache，理解 CacheBank、CMU、write-back buffer 与流水线之间的协作关系，并通过排序测试和 kernel 运行验证 cache 对访存性能的改善。实验重点不只是补全 `Cache.sv`，还包括处理 cache 接入后暴露出的流水线 stall、flush、forwarding、CSR 和 MMIO 时序问题。

## 二、设计思路

本次设计采用二路组相联 cache，每条 cache line 包含 4 个 64 bit word，整体策略以 write-back、write-allocate 和 read-priority 为基础。`CacheBank.sv` 负责 tag 比较、命中判断、数据存储、dirty/valid/LRU 更新；`Cache.sv` 中实现 CMU 状态机，负责 miss 后按 beat 从内存 refill，以及将 write-back buffer 中的脏行写回内存；`Icache.sv` 和 `Dcache.sv` 作为 CPU 与通用 Cache 模块之间的包装层，分别处理取指和数据访存。

D-Cache 额外区分普通内存和 MMIO。普通内存访问走 cache；UART、misc、conv 等 MMIO 地址直接旁路到总线，避免把外设寄存器缓存起来。为了降低某些 store miss 的开销，当前实现还加入了 store miss 直写路径：store hit 仍写 cache 并置 dirty，部分 store miss 则直接写内存而不 refill 整条 line，同时通过写通道 owner 机制避免 MMIO、store miss 和 cache write-back 共用写响应通道时互相误收响应。

Core 接入 cache 后，取指停顿由 `hit_icache` 控制，访存停顿由 `hit_dcache` 控制。由于 cache hit 时流水线可以连续提交，原先被慢总线掩盖的 RAW hazard、CSR hazard、flush/stall 优先级和 invalid bubble 副作用问题都需要重新处理。

## 三、主要实现

 CMU 状态机

`Cache.sv` 中的 CMU 使用三个状态：

- `CMU_IDLE`：空闲，等待 CacheBank 报告 miss。
- `CMU_READ`：处理 refill，依次读取 4 个 64 bit beat，并通过 `wen_rd` 写回 CacheBank。
- `CMU_WRITE`：处理 write-back buffer 中的脏行，依次写回 4 个 beat。

为了兼容内存响应可能同拍返回或跨拍返回，代码中区分了 `read_req_fire`、`read_resp_now`、`read_resp_fire`，写通道也对应区分 `write_req_fire`、`write_resp_now`、`write_resp_fire`。这样可以避免 ready-valid 握手中漏掉同拍响应，或者把“请求被接受”误判为“响应已经完成”。


 Core 接入

取指阶段使用 `if_stall = ~hit_icache` 控制 PC 和 IF/ID 寄存器停顿。访存阶段使用

```verilog
mem_stall = EXEMEM_reg.valid &&
            (EXEMEM_reg.re_mem || EXEMEM_reg.we_mem) &&
            !hit_dcache;
```

控制 MEM 阶段等待 load/store 完成。为了适应 cache 命中后一拍一条的执行节奏，补充了 EX/MEM/WB 多级 forwarding、load-use stall、CSR RAW hazard 检测，并将流水线中的副作用控制位与 `valid` 严格绑定。

## 四、Debug 过程与解决方案

### 1. CMU ready-valid 时序问题

最初实现 CMU 时，容易把读写请求发出和响应返回混在一起处理。这样在内存同拍返回时可能漏计 beat，在跨拍返回时又可能重复发请求。解决方案是在 READ/WRITE 状态中显式区分请求握手和响应握手：请求被 ready 接收时置等待标记，响应 valid 返回时才推进 `beat_count`；若请求和响应同拍发生，则通过 `*_resp_now` 直接完成当前 beat。修复后 refill 和 write-back 都能稳定完成 4 个 beat。

### 2. MMIO 重复写导致输出重复

排序测试尾部曾出现字符重复输出。对比指令流后发现程序并没有重复执行打印代码，问题出在 D-Cache 等待 MMIO 写响应时重复把同一个 UART 写请求发到总线。解决方法是在 D-Cache 中加入 `mmio_pending`、`mmio_read_pending`、`mmio_write_pending` 以及锁存寄存器。请求发出后若响应未返回，则 pending 保持有效，期间不再重复发出同一笔 MMIO 请求，直到 `rvalid_in` 或 `wvalid_in` 返回后清除。

### 3. flush 与 mem_stall 同拍导致跳转丢失

kernel 在 `printf_core` 附近曾出现跳转目标丢失。波形和日志显示，某拍 `flush=1` 与 `mem_stall=1` 同时出现，前级被清空，但携带跳转结果的指令因为 MEM 阶段 stall 没有顺利推进，导致 redirect 信息丢失。解决方案是将 flush 改为：

```verilog
flush = mispredict_exe && !mem_stall;
```

即当前面更老的访存指令尚未完成时，延后 redirect，保证产生 redirect 的指令能在流水线中正确推进。

### 4. 异常提交拍与 cosim 对齐问题

调试 `ecall` 和 `unimp` 时发现，CSR 提交需要使用与 MEM/WB 对齐的异常信息，而 cosim 过滤异常的时机又需要保持与排序测试结尾的 `unimp` 行为兼容。最终采用两套异常信息：CSR 提交使用 `except_info_ex4`，cosim 输出过滤使用 `except_info_ex5`，并对排序测试末尾的 `c0001073` 非法指令做兼容处理。这样 kernel 可以越过早期 trap 错误，同时 `verilate_sort` 仍保持“排序成功 + 末尾 unimp mismatch”的预期行为。

### 5. invalid bubble 携带旧副作用

接入 cache 后，I-cache miss 和 trap 窗口会产生 invalid bubble。调试中发现某些 bubble 虽然 `valid=0`，但仍保留旧的 `inst`、`we_csr`、`csr_ret` 等控制信息，导致过期 CSR 写或 `mret` 被误提交，表现为 `mscratch` 异常、PC 跳到错误地址。解决方案是在 IDEXE、EXEMEM、MEMWB 各级都将 `we_reg`、`we_mem`、`re_mem`、`we_csr`、`csr_ret` 等副作用控制位与当前 stage 的 `valid` 绑定，并在 invalid 时清零 `rd/rs/csr_addr/inst/pc/wb_sel/mem_op` 等字段。同时在 CSRModule 接口再加保护：

```verilog
csr_we_wb = MEMWB_reg.we_csr && MEMWB_reg.valid
csr_ret   = MEMWB_reg.valid ? MEMWB_reg.csr_ret : 2'b0
```

修复后无效 bubble 不再产生架构副作用。

### 6. 写响应通道归属问题

D-Cache 中 cache write-back、MMIO 写和 store miss 直写共用同一条写响应通道。如果没有归属标记，可能出现 A 请求发出后由 B 路径消费 `wvalid_in` 的情况。为此加入 `write_owner_q`，分为 `WRITE_OWNER_NONE`、`WRITE_OWNER_CACHE`、`WRITE_OWNER_STORE_MISS`、`WRITE_OWNER_MMIO`。只有当前 owner 对应的路径能消费写响应，响应返回后 owner 清空。该修复稳定了 store miss、MMIO 和 write-back 并存时的行为。



## 五、思考题

### 思考题 1：描述 CacheBank 模块的理解

`CacheBank` 是 cache 中真正保存数据和元信息的存储体。本设计中它是二路组相联结构，每个 index 下有两个 way，每个 way 保存一条 cache line。CPU 访问时，地址先被拆成 tag、index、offset 和字节偏移。`index` 用来选中一组，`tag` 同时和两个 way 中保存的 tag 比较，若某一路 `valid=1` 且 tag 相等，则该路命中。命中读时，模块根据 offset 从整条 cache line 中取出目标 64 bit word 返回给 CPU；命中写时，模块根据 `wmask` 按字节更新目标 word，并将该行 dirty 位置 1。

如果两路都不命中，`CacheBank` 根据 LRU 信息选择被替换的 way，输出 miss 行的行首地址 `addr_cache` 和替换路号 `set_cache`。如果被替换的 victim line 是脏的，则同时输出 `addr_wb` 和 `data_wb`，让 write-back buffer 暂存旧行。此时 `CacheBank` 本身并不负责访问内存，它只负责命中判断、数据读写、dirty/valid/LRU/tag 状态更新；真正的 refill 和 write-back 由外部 CMU 完成。

### 思考题 2：cache hit、miss、write back 的波形与周期分析

本题主要观察 `Testbench.dut.core.core.dcache.cache` 层级下的信号。`cmu_state` 的编码为 `00 = CMU_IDLE`、`01 = CMU_READ`、`10 = CMU_WRITE`。其中 `miss_cache` 表示 CacheBank 判断本次 CPU 请求未命中，`need_wb` 表示被替换的 victim line 为 dirty，需要写回；`read_resp_fire` 和 `write_resp_fire` 分别表示一次 refill/write-back beat 的响应真正被 cache 接收。

#### 1. Cache hit

![Cache hit 波形截图]()

Cache hit 时，波形中可以看到 `ren_cpu=1` 或 `wen_cpu=1`，同时 `hit_cpu=1`、`miss_cache=0`，状态机保持在 `cmu_state=00`。这说明 tag 比较已经在 `CacheBank` 内命中，读数据可以直接由命中的 cache line 根据 offset 取出；如果是 store hit，则直接按 `wmask_cpu` 更新 cache line，并将 dirty 位置 1。

hit 过程中 `ren_mem=0`、`wen_mem=0`，说明 cache 不需要向下层 memory 发起 refill 或 write-back。对流水线来说，D-cache 的 `hit_cpu=1` 会让外层 `hit_dcache` 为真，MEM 阶段不会因为本次访存继续 `mem_stall`。因此 cache hit 的额外访存等待周期近似为 0，是当前 cache 设计中最快的访问路径。

#### 2. Cache miss 与 refill

![Cache miss refill 波形截图]()

以排序测试中的一次 D-cache miss 为例，CPU 访问地址 `0x80003fcc` 时，波形中先出现 `miss_cache=1`、`hit_cpu=0`，同时 `addr_cache=0x80003fc0`。`addr_cache` 是按 cache line 对齐后的 refill 基地址，说明本次 miss 要从 `0x80003fc0` 开始读回整条 cache line。

miss 被 CMU 接收后，`cmu_state` 从 `00` 进入 `01`，即 `CMU_READ`。在 READ 状态下，cache 通过 `ren_mem` 和 `raddr_out` 向下层 memory 请求数据。由于一条 cache line 包含 4 个 64 bit word，所以 refill 过程需要 4 个 beat。波形中可以看到 `read_resp_fire` 出现 4 次，`beat_count` 依次为 `0, 1, 2, 3`，对应写入 CacheBank 的地址为：

```text
addr_rd = 0x80003fc0
addr_rd = 0x80003fc8
addr_rd = 0x80003fd0
addr_rd = 0x80003fd8
```

每次 `read_resp_fire=1` 时，`wen_rd=1`，表示当前 beat 的 `rdata_in` 被写入 CacheBank。最后一个 beat 返回时，`beat_count=3` 且 `finish_rd=1`，说明整条 cache line refill 完成，随后状态机回到 `CMU_IDLE`。在下一次访问同一地址时，`hit_cpu` 拉高，说明刚才读回的 line 已经可以正常命中。

根据本次波形对应的计数，`miss_cache` 出现在 `cyc=358`，最后一个 refill beat 在 `cyc=374` 完成，因此从发现 miss 到 `finish_rd` 约为：

```text
374 - 358 + 1 = 17 cycles
```

如果只统计 memory 返回数据阶段，第一个 `read_resp_fire` 在 `cyc=362`，最后一个在 `cyc=374`，约为 13 cycles。报告中按完整 miss penalty 统计，即一次 clean miss/refill 大约消耗 17 个 core cycles。

#### 3. Dirty miss 与 write-back

![D-cache write-back 波形截图]()

运行 kernel 时可以观察到 D-cache dirty line 被替换的情况。波形中在 `t=60285000` 附近，CPU 访问 `addr_cpu=0x80000660`，同时出现：

```text
miss_cache = 1
need_wb    = 1
addr_wb    = 0x80202e60
```

这说明当前访问 miss，并且被替换出去的 victim line 是 dirty line，需要先把旧数据写回 memory。`addr_wb=0x80202e60` 是 victim line 的写回基地址。此时 `CacheBank` 会把 victim line 的地址和数据送入 `CacheWriteBuffer`，由 write-back buffer 暂存待写回的数据。

当前 CMU 采用 read-priority 策略。也就是说，在 dirty miss 出现后，状态机先进入 `CMU_READ`，优先把 CPU 当前需要的新 line refill 回来；当 `finish_rd=1` 且 `busy_wb=1` 时，状态机再进入 `CMU_WRITE` 处理旧脏行写回。这样当前 miss 的关键路径主要等待 refill，旧 line 的 write-back 被放到 refill 之后完成。

在 write-back 阶段，波形中可以看到 `cmu_state=10`，`wen_mem=1`。随后 `write_resp_fire` 出现 4 次，`beat_count` 依次为 `0, 1, 2, 3`，写地址按 8 字节递增：

```text
waddr_out = 0x80202e60
waddr_out = 0x80202e68
waddr_out = 0x80202e70
waddr_out = 0x80202e78
```

最后一个 beat 时 `beat_count=3`、`write_resp_fire=1`、`finish_wb=1`，说明整条 dirty cache line 已经写回完成。之后 `busy_wb` 清除，CMU 可以回到 `CMU_IDLE` 或继续处理后续请求。

本次 kernel 波形中，dirty miss 被发现于 `cyc=3013`，write-back 的 4 个 beat 响应分别出现在 `cyc=3034`、`3039`、`3044`、`3049`。因此从 dirty miss 发现到 write-back 完成约为：

```text
3049 - 3013 + 1 = 37 cycles
```

如果只统计 write-back 本身，从第一个 `write_resp_fire` 到 `finish_wb` 约为：

```text
3049 - 3034 + 1 = 16 cycles
```

综合来看，cache hit 不访问 memory，代价最小；clean miss 需要 4 个 beat refill；dirty miss 在 refill 之外还会触发 4 个 beat write-back，因此总代价最高。不过由于当前设计把 dirty victim 暂存在 write-back buffer 中，并优先 refill 新 line，CPU 当前请求不必先完整等待旧 line 写回，从而降低了 dirty miss 对关键路径的影响。

### 思考题 3：启用 cache 前后的排序测试 CPI 对比

统计方法为：在仿真 `testbench.sv` 中临时加入 `$display` 和两个计数器。从 `rstn=1` 后开始，每个 `core_clk` 上升沿将总周期数加 1；如果同拍 `cosim_valid=1`，则将有效提交指令数加 1。排序测试最后会因为预期的 `unimp` mismatch 进入 testbench 的 `error` 分支，因此在 `$finish` 前打印周期数、提交数和 CPI。CPI 计算公式为：

```text
CPI = core_clk 周期数 / cosim_valid 有效提交指令数
```

具体加入位置为临时仿真文件 `/tmp/sim_cpi_display/testbench.sv` 的 `ifdef VERILATE` 块内，放在 `difftest` 和 `SimUart` 实例化之后、原有 `reg [31:0] cnt` 超时计数器之前。随后在原本的 `if(error)` 和 `else if(cnt==max_sim_cycle)` 分支中，在 `$display("[CJ] ...")` 和 `$finish` 之前调用 `show_cpi()`。该修改只用于统计实验数据，没有写入正式 `submit`。

加入的代码如下：

```verilog
longint unsigned core_cycle_cnt = 64'd0;
longint unsigned commit_cnt = 64'd0;

always @(posedge core_clk or negedge rstn) begin
    if (!rstn) begin
        core_cycle_cnt <= 64'd0;
        commit_cnt <= 64'd0;
    end else begin
        core_cycle_cnt <= core_cycle_cnt + 64'd1;
        if (cosim_valid) begin
            commit_cnt <= commit_cnt + 64'd1;
        end
    end
end

task automatic show_cpi;
    real cpi;
    begin
        if (commit_cnt != 0) begin
            cpi = $itor(core_cycle_cnt) / $itor(commit_cnt);
            $display("[CPI] core_cycles=%0d commits=%0d cpi=%0.6f",
                     core_cycle_cnt, commit_cnt, cpi);
        end else begin
            $display("[CPI] core_cycles=%0d commits=0 cpi=inf",
                     core_cycle_cnt);
        end
    end
endtask
```

在原有结束分支中调用：

```verilog
always @(negedge clk) begin
    cnt <= cnt + 32'b1;
    if (error) begin
        show_cpi();
        $display("[CJ] something error");
        $dumpoff;
        $finish;
    end else if (cnt == max_sim_cycle) begin
        show_cpi();
        $display("[CJ] no simulation time");
        $dumpoff;
        $finish;
    end
end
```

这样统计的原因是：启用 cache 后流水线可能连续多个周期都有 `cosim_valid=1`，不能再简单地在 GTKWave 中搜索高电平区间个数，否则会把连续提交的多条指令误算成一次。把计数器直接放进 testbench 后，仿真结束时可以直接得到结果，不需要额外解析波形。

本次无 cache 版本使用 `3240106403_lab1` 目录中的 lab1 源码，并通过单独构建目录运行：

```text
make verilate_sort DIR_SRC=/home/zzc/sys3-sp26/src/project/3240106403_lab1 SIM_BUILD=/tmp/lab1_cpi_verilate
```

统计结果为：

```text
[CPI] core_cycles=316628 commits=34705 cpi=9.123412
```

当前带 cache 版本使用 `submit` 目录中的 lab2 源码，统计结果为：

```text
[CPI] core_cycles=51167 commits=34705 cpi=1.474341
```

两次运行的提交指令数都是 `34705`，说明统计的是同一个排序测试路径。无 cache 版本的 CPI 为：

```text
316628 / 34705 = 9.123412
```

带 cache 版本的 CPI 为：

```text
51167 / 34705 = 1.474341
```

启用 cache 后，整体 CPI 从 **9.123412** 降低到 **1.474341**，降低了约 **83.84%**；带 cache 的 CPI 约为无 cache 的 **16.16%**。按总周期数比较，运行周期从 `316628` 降到 `51167`，约提升 **6.19 倍**。

无 cache 版本 CPI 高的主要原因是取指和访存都需要直接走总线，几乎每条指令都要等待外部 memory/AXI 交互完成；排序程序中又包含大量 load/store 和输出相关 MMIO 操作，因此平均每条指令要消耗多个周期。启用 cache 后，绝大多数重复取指和普通数据访问都能在 I-Cache/D-Cache 中命中，流水线可以连续推进，只有首次访问 miss、脏行写回、load-use/CSR hazard、分支 flush 和 MMIO 旁路等情况会继续带来停顿。因此 cache 显著降低了平均访存代价，排序测试的整体 CPI 接近理想流水线状态。

