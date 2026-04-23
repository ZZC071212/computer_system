# Lab2 Cache Progress

日期：2026-04-01

## Token 续做说明

- 我不能直接读取系统里的剩余 token 数，只能根据上下文长度和工具输出体量做近似判断。
- 为了避免在接近上限时丢失工作现场，这份文件会作为续做报告持续更新。

## 2026-04-01 最新进展（以本节为准）

- 下面旧章节里关于“`kernel` 当前卡在 `printf_core`”的结论已经过时，本节覆盖它们。
- `verilate_sort` 的目标状态仍然保持不变：
  - 输出只打印一份。
  - 末尾保留实验文档要求的 `unimp` 收尾 mismatch，不再尝试消掉它。
- `kernel` 已经连续推进过两个旧故障点：
  - 不再卡在 `mm_init -> free_pages` 超时。
  - 不再死在 `printk -> vfprintf -> printf_core` 的 jump / trap 对拍错误。
- 当前最新失败点已经后移到 `schedule` 路径里的数据错误：
  - 对拍报错：`WDATA SIM 0000000000000003, DUT 0000000000000000`
  - 关键 PC：`000000008020149c`
  - 报错信息：`check board clear 14 error`

## 2026-04-02 续做补充（覆盖今天的尝试）

- 下面这段是今天继续推进后的最新结论，优先级高于本节后面的旧记录。
- 这次我参考了 `CACHE_examine.md` 里“先保 correctness、不要被表面超时迷惑”的建议，但没有直接按它对 D-cache stale-line 的判断继续挖。
  - 真实根因先落在了 `Core.sv` 的 invalid bubble 副作用上，而不是 `CSRModule.sv` 本体。
- 新确认的关键根因：
  - `IFID_reg.valid=0` 的无效气泡仍会带着陈旧 `inst` 被 decode；
  - 这些 bubble 继续生成旧的 `we_reg/we_mem/we_csr/csr_ret` 控制位，并一路推进到后级；
  - `CSRModule` 之前又直接吃 `MEMWB_reg.we_csr` / `MEMWB_reg.csr_ret`，没有再用 `MEMWB_reg.valid` 做硬门控。
  - 结果就是：
    - I-cache miss 或 trap 切换窗口里的 invalid bubble，会把过期的 `csrrw mscratch` / `mret` 当成真实退休指令提交；
    - 这正好解释了旧日志里反复出现的现象：
      - `memwb_inst=34011173, memwb_valid=0`
      - 随后 `0x800001e4` 偶发读到坏的 `mscratch`
      - 最终炸成 `PC SIM 00000000800000bc, DUT 0000000000000030`
- 已保留的新修复：
  - `Core.sv`
    - 在 `IDEXE/EXEMEM/MEMWB` 三个阶段，把所有会产生架构副作用的控制位都与对应 stage 的 `valid` 绑定；
    - 典型包括：
      - `we_reg`
      - `we_mem`
      - `re_mem`
      - `we_csr`
      - `csr_ret`
    - 同时对 `rd/rs/csr_addr/inst/pc/wb_sel/mem_op` 等字段在 invalid 情况下清零，避免 bubble 携带陈旧控制信息继续传播。
  - `Core.sv -> CSRModule` 接口
    - `csr_we_wb` 改成 `MEMWB_reg.we_csr && MEMWB_reg.valid`
    - `csr_ret` 改成 `MEMWB_reg.valid ? MEMWB_reg.csr_ret : 2'b0`
    - 这层门控是额外保险，防止任何 invalid `mret/sret/csr write` 再次提交。
- 这轮验证结果：
  - `make verilate_sort`
    - 日志：`/tmp/sort_bubble_gate.log`
    - 结果保持正确：
      - 排序输出正常；
      - 末尾仍保留实验要求的 `unimp` mismatch。
  - `make kernel`
    - 日志：`/tmp/kernel_bubble_gate.log`
    - 结果有实质推进：
      - 旧的 `0x800001e4@34011173 CSR UNMATCH` 已经消失；
      - 旧的致命分叉
        - `PC SIM 00000000800000bc, DUT 0000000000000030`
        - `INSN SIM 34011173, DUT 34029073`
        也没有再出现；
      - 仿真最终停在 testbench 的 50ms 时间上限：
        - `[CJ] no simulation time`
      - 这次没有 `Commit Failed`，说明之前把 kernel 打崩的主故障已经被拔掉。
- 还剩下的单点问题：
  - 目前 `kernel` 日志里还留有一个孤立 warning：
    - `0000000080000200@344027f3 CSR UNMATCH`
    - 指令是 `csrr a5, mip`
    - 首次失配表现为 `SIM 0x0, DUT 0x80`
  - 这看起来更像 `mip/mtip` 可见性或 timer pending 位时序的局部差异，而不是之前那种会把执行流直接带偏的系统性故障。
  - 后续如果继续做，下一优先级应转到：
    - `CSRModule.sv` 里 `mip` / `time_int` / `MTIP` 的可见性时序；
    - 而不是再回去追已经解决掉的 `mscratch` 活锁/错写问题。
- 当前仍未收尾的工程项：
  - `Core.sv` 里的 `[CORE-PIPE] / [CORE-WB] / [CORE-TRAP] / [CORE-CSR]` 调试打印还在；
  - `Dcache.sv` / `Cache.sv` 的临时打印也还在；
  - 在最终提交前仍需要统一清理。

- `CACHE_examine.md` 里“`kernel` 仍卡在 `free_pages`、store-miss 状态机未补全”的审查结论已经不再代表当前真实状态。
  - 这次我重新核对了代码和日志，确认真正的工作基线仍然是：
    - `Core.sv` 已保留 jump/trap 的时序修复；
    - `Dcache.sv` 是“store miss 直写、不 refill；并阻止它与 cache 普通写请求同拍抢占写通道”的那版；
    - 这版不会立刻对拍炸掉，但 `kernel` 仍然跑不通。
- 我强制清理并重编了 kernel，确认 `private_kdefs.h` 的修改确实生效。
  - 通过反汇编可以看到 `mm_init()` 里比较的物理上界已经变成了 `0x80220000`。
  - 这说明之前 `PHY_SIZE` 改小后“现象没变”，不是因为头文件没生效，而是因为真正的阻塞点已经不在 `free_pages`。
- 新的最关键定位结果：
  - `task_init()` 最后一次循环里，执行到 `0x80201334: ld a5, 0(s1)` 时会卡住。
  - 对应地址是 `0x80204040`，也就是 `task[4]` 的指针槽。
  - 临时 debug 已经确认：
    - 这个 `ld` 并没有消失，而是每拍都在重试；
    - D-cache 一直处于 `busy=1`；
    - 同时还能看到 cache 侧残留 `wb_busy=1`，关联的 victim line 是任务页一侧的脏行。
  - 这说明这里不是“单纯太慢”，而是 cache/store-miss/writeback 之间存在真实的活锁或响应归属问题。
- 这次已经尝试并证伪的修法：
  1. 只让 `Cache.sv` 在 `CMU_IDLE` 时主动清空 `busy_wb`
     - 不能解决上面的卡死。
  2. 让 direct store miss 在 `busy_cache` 或 `write_busy_cache` 时不允许发射
     - 的确能把 `task_init` 的卡点推过去；
     - 但会重新引出旧的早期 trap/jump 对拍错误：
       - `PC SIM 00000000800000bc, DUT 0000000000000030`
       - `INSN SIM 34011173, DUT 34029073`
     - 这和之前已经见过的“store-miss 时序一改，trap 路径就炸”是同一类回归，所以不能保留。
- 结论：
  - `PHY_SIZE` 继续缩小不是有效方向；
  - “简单地把 direct store miss 全部压到 cache 空闲后再发”也不是可接受解；
  - 当前最可信的未解根因是：
    - direct store miss 和 cache writeback 仍然共享同一条无标签的写响应路径；
    - 在某些时序下，写响应归属或 writeback 进度仍会被串坏；
    - 但如果把 store miss 彻底串行化，又会重新暴露 Core 里旧的 trap/mem_stall 故障。
- 因此，这一轮结束时我已把代码收回到之前“不会立刻对拍炸掉”的安全基线，避免把今天试错后的坏状态留下来。

## 本轮新增定位结论

- `Core.sv` 里已经确认并修复了一个真实的流水线控制错误：
  - 现象：`printf_core` 中跳转 `0x802007fc -> 0x80200874` 会丢失。
  - 根因：`flush=1` 与 `mem_stall=1` 同拍时，前级被清空，但带跳转的指令被卡在 `IDEXE` 没能推进到 `EXEMEM`，导致跳转直接丢了。
  - 修复：`flush = mispredict_exe && !mem_stall;`
  - 含义：若前面还有老的访存指令没走完，就延后这次 redirect，避免丢控制流。
- `Core.sv` 里还确认并修复了 trap 提交时序错位：
  - 现象：`ecall` 到了 `MEMWB` 时，`except_info_ex4.except=1`，但 `except_info_ex5.except=0`，说明两者对齐拍不同。
  - 修复策略：
    - `CSRModule.except_commit` 改为使用与 `MEMWB` 对齐的 `except_info_ex4`
    - 但 `cosim_valid` 继续基于较晚一拍的异常可见性，避免把 `sort` 末尾预期的 `unimp` 行为破坏掉
  - 结果：`kernel` 成功越过第一次 `ecall -> trap` 失配点。

## 当前最可能的根因

- 当前失败已经不像是控制流问题，更像是 D-cache 数据一致性问题。
- 现在 `Dcache.sv` 里存在一版实验性的“store miss 直写内存、不做 line refill”逻辑；它确实把 `kernel` 从 `free_pages` 超时推进过去了，但也引入了新的可疑点。
- 结合最新调试日志，已经看到下面这种情况：
  - 某些地址所在 cache line 先被 load miss 从内存 refll 进 cache，当时该 line 的后半部分在内存里还是 0。
  - 随后同一 line 上的部分 store 是 cache hit，只改了 cache 内部内容。
  - 更后面的 load 又命中这条 line，读到的仍可能是旧值 0。
- 最新直接证据：
  - `schedule` 在读取 `0x803fc010` 时，DUT 通过 D-cache hit 读到了 `0`。
  - 但参考模型期望值是 `3`。
  - 这说明问题不是“没访问到内存”，而是“cache 中当前驻留的 line 数据已经陈旧或不一致”。

## 已记录的关键地址与现象

- `schedule` 失败点：
  - `0x8020149c: ld a4, 16(a2)`
- 相关全局数组：
  - `task[]` 位于 `0x80204020 .. 0x80204040`
- 相关任务页：
  - `0x803fb000 .. 0x803ff000`
- 关键调试现象：
  - `0x80204020` 这一整条 line 曾被 refill 进 D-cache，当时 beat2 / beat3 还是 0。
  - 后续对 `0x80204030`、`0x80204038` 的写入是 cache hit store，不是 direct store miss。
  - 最终失败前，日志里明确出现：
    - `0x80204038` 的 hit load 读出了合法 task 指针
    - 随后 `0x803fc010` 的 hit load 直接读出了 `0`

## 当前代码的真实状态

- `src/project/submit/Core.sv`
  - 应保留的修复：
    - `flush = mispredict_exe && !mem_stall`
    - `CSRModule.except_commit` 使用与 `MEMWB` 对齐的异常提交信息
    - `cosim_valid` 继续保持与 `sort` 预期兼容的异常过滤策略
  - 仍残留临时调试打印：
    - `[CORE-PIPE]`
    - `[CORE-WB]`
    - `[CORE-TRAP]`
- `src/project/submit/Dcache.sv`
  - 仍保留实验性的 store-miss direct-write 逻辑。
  - 仍残留临时调试打印：
    - `[DCACHE-SM]`
    - `[DCACHE-SM-ACT]`
    - `[DCACHE-HIT-ST]`
    - `[DCACHE-HIT-LD]`
- `src/project/submit/Cache.sv`
  - 还保留过一次 miss/refill/writeback 相关的临时打印，最终提交前要统一清理。

## 当前最有价值的日志

- `/tmp/kernel_fix3.log`
  - 记录了修完 jump / trap 后，`kernel` 已经运行到约 4ms，最终在 `schedule` 读错数据处失配。
- `/tmp/kernel_dcache_dbg.log`
  - 记录了 `task[]` 与任务页相关地址上的 D-cache store-miss / hit / load 行为，是目前最关键的现场证据。
- 旧日志仍有历史价值：
  - `/tmp/kernel_pipe_dbg.log`
  - `/tmp/kernel_trap_dbg.log`

## 对代码审查意见的取舍

- `CACHE_examine.md` 之前那版审查意见主要停留在“store miss 逻辑未补全、`kernel` 仍卡 `free_pages`”这一阶段。
- 这部分结论现在已经落后于真实进度，所以这次没有直接照单执行，而是保留作历史参考。
- 如果代码审查师后续又更新了文件，续做时要优先核对它是否覆盖到了：
  - `printf_core` 跳转丢失
  - `ecall/trap` 提交时序
  - `schedule` 处的 D-cache stale line 问题

## 下一步建议动作

1. 优先围绕 `Dcache.sv` 的 store-miss 策略做收敛，不要再把时间花在旧的 `printf_core` / `trap` 故障上。
2. 一个直接可做的验证是：
   - 保留 `Core.sv` 已修好的控制流与异常提交逻辑；
   - 临时回退 `Dcache.sv` 的 store-miss direct-write 策略，重新跑 `kernel`；
   - 对比它是重新回到 `free_pages` 超时，还是能走得更远。
3. 如果确认问题确实来自 direct-write 策略，就需要在下面两条里选一个最终方向：
   - 回到一致性更简单的 write-allocate 方案，再想办法降低超时风险；
   - 或保留 no-allocate / direct-write，但补齐与已缓存 line 之间的一致性维护。
4. 最终交付前必须删掉所有临时 `VERILATE` 打印，并回归：
   - `make verilate_sort`
   - `make kernel`

## 当前结论

- `verilate_sort` 现在的正确现象已经恢复：
  - 排序输出只打印一份。
  - 最后保留实验文档中提到的 `unimp` 收尾对拍失败。
- 之前用户看到的“尾部像成功输出但字符重复、成功信息重复打印”，根因已经定位并修复：
  - `src/project/submit/Dcache.sv`
  - MMIO 旁路在等待响应时会重复发请求，导致 UART 输出被重复消费。
- `kernel` 还没有通过，但状态已经前进了一大步：
  - 旧问题是卡在 `mm_init -> free_pages` 超时。
  - 新问题是已经能进入 `printk -> vfprintf -> printf_core`，随后发生对拍失配。

## 已完成的主要修改

- `src/project/submit/Cache.sv`
  - 完成了 CMU 的 READ/WRITE 状态机。
  - 增加了对“请求握手和响应同拍完成”的处理。
- `src/project/submit/CacheBank.sv`
  - 改写为更稳定的数组实现，避免 Verilator 对 struct-array 的问题。
  - 修复 refill 完成后没有更新 LRU 的问题。
- `src/project/submit/Dcache.sv`
  - 修正了地址映射，使用 `MemPack` 里的内存/MMIO 边界。
  - 修复 MMIO 请求等待期间的重复发射。
  - 已加入一版“store miss 直写内存、不做 line refill”的实验性逻辑。
- `src/project/submit/Core.sv`
  - 已接入 `Icache` / `Dcache`。
  - 修过多处流水线问题：
    - CSR RAW hazard
    - CSR / `WB_SEL_PC` forwarding
    - load-use stall
    - `WB_SEL_MEM` forwarding
    - `mispredict_exe` 判定
    - `mem_stall` 下保持/清空优先级
- `src/project/submit/IDExceptExamine.sv`
  - 扩展非法指令检查，使 `unimp (0xc0001073)` 被正确识别。

## sort 的最终判断

- `docs/lab1.md` 已明确说明：
  - `make verilate_sort` 正确情况下本来就会在 `[+] sort test succeed!` 后出现最后一条 `PC/INSN mismatch`。
  - 这是用 `unimp` 把仿真停下来的预期行为，不应继续屏蔽掉这一拍。
- 所以：
  - 之前把异常和 `cosim_valid` 完全对齐、试图消掉最后 mismatch 的改动已经撤回。
  - 当前应继续保持“排序输出正常，末尾 mismatch 停机”的语义。

## kernel 旧问题的定位

- 原始 `kernel` timeout 并不是普通的“慢一点”，而是 cache miss 代价异常大。
- 旧日志和临时打印已经确认：
  - `free_pages` 相关地址：
    - freelist 头：`0x0000000080204008`
    - 页头：`0x0000000080205000 / 0x6000 / 0x7000 ...`
  - 旧 write-allocate 行为：
    - `0x80204008` load miss，4-beat refill
    - 每个新页头 `sd` 都触发 4-beat refill
    - 脏页头替换还会带来 4-beat writeback
- 关键结论：
  - 在当前 AXI 包装下，每个 64-bit beat 的 refill / writeback 间隔都很大。
  - 不是逻辑上“完全不动”，而是 miss 路径成本高到会把 `kernel` 50ms 仿真时间耗尽。

## 当前实验性方案

- 为了打掉 `free_pages` 的热点，我给 D-cache 做了一版实验性策略：
  - load miss：仍然正常 refill cacheline
  - store hit：仍然写 cache
  - store miss：直接发单次写请求到内存，不做整条 line refill
- 这版代码已经补全了 `store_miss_pending` 状态机，不再是“半改完”状态。

## 本轮最新验证结果

- 使用新的独立构建目录完成了完整 `kernel` 验证：
  - `SIM_BUILD=/tmp/verilate_storemiss_kernel`
  - 日志：`/tmp/kernel_full_storemiss.log`
- 这次运行的关键变化：
  - 不再卡死在 `free_pages`
  - 执行流已经推进到：
    - `printk`
    - `vfprintf`
    - `printf_core`
- 说明：
  - “store miss 成本过高导致 kernel 超时”这个方向是对的。
  - 新策略确实把执行推进过去了。

## 新暴露出的故障

- 新版本 `kernel` 不是超时，而是很快在对拍中失败。
- 关键信息：
  - `PC SIM 00000000802007fc, DUT 0000000080200874`
  - `INSN SIM 0780006f, DUT 800007b7`
  - 后续又出现：
    - `0000000080201290@f6878793 check board clear 15 error`
    - `WDATA SIM 00000000802011f4, DUT ffffffff80000000`
- 从汇编和运行日志对照看：
  - 失败点已经在 `printf_core` 路径里。
  - 在失败前，`auipc a5`、`addi a5, a5, -152`、`sd a5, 8(sp)` 这些指令都已经按 trace 正常执行。
  - 所以后面的寄存器 judge 失败，大概率是前面的 jump / 提交顺序出了问题，导致 checkboard 没按预期清空，而不一定是 `addi` 本身算错。

## 当前推断

- 现在最值得怀疑的不是 `free_pages` 本身，而是：
  - 新的 `store miss` 旁路改变了 `mem_stall` 的时序，
  - 提前暴露了一个控制流 / 提交次序问题。
- 当前优先怀疑方向：
  - jump/branch 在新的 `mem_stall` 时序下被跳过提交
  - 或者 store-miss 旁路的 `hit_cpu` / `wen_mem` 返回时机让某条跳转指令没有按预期进入 cosim 提交流

## 当前工作区的真实状态

- `src/project/submit/Dcache.sv`
  - 已经实现了第一版 store-miss 直写逻辑。
  - 这版逻辑能显著推进 `kernel`，但会触发新的对拍错误，所以还不是最终方案。
- `src/project/submit/Cache.sv`
  - 目前还保留了一段临时 `VERILATE` 调试打印：
    - `[CACHE-MISS]`
    - `[CACHE-READ]`
    - `[CACHE-REFILL-DONE]`
    - `[CACHE-WRITEBACK]`
    - `[CACHE-WB-DONE]`
  - 这段打印是为了确认 `kernel` miss 路径时序，最终提交前需要删掉。

## 直接可用的调试证据

- 旧 timeout 调试日志：
  - `/tmp/kernel_run_dbg.log`
- 新的完整 kernel 运行日志：
  - `/tmp/kernel_full_storemiss.log`
- 新的独立构建目录：
  - `/tmp/verilate_storemiss_kernel`

## 续做顺序

1. 保留当前 `store miss` 直写版本，围绕新的故障点继续查：
   - `printf_core` 路径里的 jump / commit 顺序
   - 新的 store-miss 旁路返回时机是否让某条跳转被跳过提交
2. 继续验证时，优先直接用独立构建目录，避免旧 build 目录里损坏的 PCH 中间件：
   - `CCACHE_DISABLE=1 make kernel SIM_BUILD=/tmp/verilate_storemiss_kernel`
3. 同时保留对 `sort` 的回归检查：
   - `make verilate_sort`
   - 目标依旧是一份正确输出 + 末尾 expected mismatch
4. 若 `kernel` 最终通过，再删除：
   - `Cache.sv` 临时调试打印
   - 若最终放弃 store-miss 直写方案，也要把 `Dcache.sv` 里的实验性逻辑回收或整理干净

## 需要特别注意的点

- 不要再试图消掉 `sort` 末尾的 `unimp` mismatch。
- 现在最有价值的日志已经不再只是旧的 `/tmp/kernel.err`，而是：
  - `/tmp/kernel_full_storemiss.log`
- `docs` 目录下原本就有未提交改动，和这次工作无关，不要动。
