### 发现的问题（2026-04-02 重新审查）

作为代码审查师，我于 2026-04-02 重新审查了项目状态。经过实际运行验证和代码审查，我发现 `CACHE_examine.md` 中之前的审查结论已经**严重落后于真实进度**。以下是基于最新验证的审查结果：

#### 当前真实现状（经实际运行验证）

1. **verilate_sort 测试**：✅ **通过**
   - 输出正确：`[+] sort test succeed!`
   - 末尾有预期的 PC/INSN mismatch（由 `unimp` 指令导致的预期行为）
   - 这符合实验文档要求

2. **kernel 运行状态**：⚠️ **部分通过，已大幅推进**
   - 之前审查称"卡在 free_pages 超时"已过时
   - 实际运行显示：已经成功执行到任务调度和打印相关代码
   - 最终因仿真时间耗尽（50ms）而停止：`[CJ] no simulation time`
   - 关键证据：日志中出现了大量 task 相关地址的 cache 访问（`0x80204020..0x80204040`）

#### 已确认的代码修复（经代码审查验证）

1. **Core.sv 中的关键修复**：
   - ✅ **跳转丢失修复**（第 609 行）：`flush = mispredict_exe && !mem_stall;`
     - 根因：`flush=1` 与 `mem_stall=1` 同拍时，带跳转的指令被卡在 `IDEXE` 没能推进到 `EXEMEM`
     - 修复：延后 redirect，避免丢控制流
   - ✅ **trap 提交时序修复**（第 304 行）：
     - `except_commit_wb = except_info_ex4;`（与 MEMWB 对齐）
     - `except_cosim_wb = except_info_ex5;`（保持与 cosim 的兼容性）
     - 这解决了 `ecall` 异常信息传递不同拍的问题

2. **Dcache.sv 中的实验性修改**：
   - ⚠️ **store miss 直写逻辑**（第 178-247 行）：
     - 实现了 `store_miss_pending` 状态机
     - store miss 时直接发单次写请求到内存，不做 line refill
     - 这是为了降低 `free_pages` 中页头写入的 miss 代价
   - ⚠️ **残留调试打印**：保留了 `[DCACHE-SM]`、`[DCACHE-HIT-ST]` 等 VERILATE 打印

3. **Cache.sv 中的实现**：
   - ✅ **CMU 状态机已完成**：包含 CMU_IDLE、CMU_READ、CMU_WRITE 三个状态
   - ⚠️ **残留调试打印**：保留了 `[CACHE-MISS]`、`[CACHE-READ]` 等 VERILATE 打印

#### 当前最可能的根因分析

根据日志和代码审查，当前 kernel 未能完全通过的原因更可能是：

1. **Cache 数据一致性问题**（高可能性）：
   - `CACHE_PROGRESS.md` 中记录的关键证据：
     - `0x80204020` 这一整条 line 曾被 refill 进 D-cache，当时 beat2/beat3 还是 0
     - 后续对 `0x80204030`、`0x80204038` 的写入是 cache hit store
     - 最终失败前，`0x803fc010` 的 hit load 直接读出了 0（期望值非 0）
   - 这说明问题不是"没访问到内存"，而是"cache 中当前驻留的 line 数据已经陈旧或不一致"

2. **store miss 直写策略的副作用**（中可能性）：
   - 当前的 direct-write 策略虽然降低了 miss 成本，但可能引入了一致性问题
   - 特别是当某个 address 先被 load miss refill（数据不全），然后同一 line 上的其他地址发生 store miss 直写时，可能导致数据不一致

3. **性能问题**（次要因素）：
   - 即使有 store miss 优化，kernel 仍然在 50ms 内未能完成
   - 这可能是因为 AXI 包装下每个 beat 的间隔仍然很大

#### 与之前审查结论的对比

| 审查项 | 之前结论 | 实际现状 | 评价 |
|--------|----------|----------|------|
| verilate_sort | 通过 | 通过 | ✅ 正确 |
| kernel 是否卡 free_pages | 是，超时 | 否，已越过 | ❌ 过时 |
| store miss 状态机 | 未完成 | 已完成 | ❌ 过时 |
| Core.sv 修复 | 未提及 | 已修复 jump/trap | ❌ 遗漏 |
| 当前阻塞点 | free_pages | schedule 数据一致性 | ❌ 过时 |

### 改进建议与下一步行动

#### 立即建议（按优先级排序）

1. **优先验证数据一致性问题**（最高优先级）：
   - 建议程序员临时关闭 store miss 直写策略，回退到纯 write-allocate
   - 重新运行 kernel，观察它是回到 free_pages 超时，还是能走到 schedule 阶段
   - 如果回退后能走得更远，说明直写策略确实引入了一致性问题

2. **清理调试代码**（高优先级）：
   - 删除 `Cache.sv` 中的所有 `#ifdef VERILATE` 调试打印
   - 删除 `Dcache.sv` 中的调试打印
   - 这些打印会影响综合工具的性能，且不属于最终提交内容

3. **深入调查 cache line stale 问题**（中优先级）：
   - 重点检查 `0x80204020` 这一行的生命周期：
     - 何时被 load miss refill？
     - refill 时的数据来源是什么？
     - 后续的 store hit 是否正确更新了 cache line？
     - 为什么后来的 load 会读到旧数据？
   - 可能需要检查 CacheBank 的 hit/miss 判断逻辑

4. **考虑调整 cache 策略**（架构级建议）：
   - 如果直写策略确实导致一致性问题，可以考虑：
     - 方案 A：回到 write-allocate，但尝试减少 refill 的 beat 数或优化 AXI 时序
     - 方案 B：保留直写，但增加 invalidate 机制，确保已缓存 line 的数据新鲜度

5. **增加性能监控**（辅助工具）：
   - 建议在 testbench.sv 中添加 CPI 计算逻辑
   - 统计 cache hit/miss 比例
   - 这有助于量化不同策略的效果

#### 代码质量评价

| 维度 | 评分 | 说明 |
|------|------|------|
| 功能完整性 | ⭐⭐⭐☆☆ | CMU 状态机完成，但 kernel 仍未完全通过 |
| 代码正确性 | ⭐⭐⭐☆☆ | Core.sv 关键修复正确，但 cache 一致性存疑 |
| 代码整洁度 | ⭐⭐☆☆☆ | 残留较多调试打印，需在提交前清理 |
| 调试深度 | ⭐⭐⭐⭐⭐ | 定位深入，有详细的日志和时序分析 |
| 文档同步性 | ⭐⭐⭐⭐☆ | CACHE_PROGRESS.md 更新及时，但需警惕过度承诺 |

### 审查师总结

程序员的工作进展**显著优于**我之前审查报告中的判断。主要成就包括：

1. ✅ 成功修复了 Core.sv 中的多个流水线控制错误（jump 丢失、trap 时序）
2. ✅ 完成了 Cache CMU 状态机的实现
3. ✅ 显著推进了 kernel 的执行进度（从卡 free_pages 到进入调度器）
4. ✅ 保持了 verilate_sort 的正确性

当前剩余的主要挑战是**D-cache 数据一致性与性能的平衡**。建议程序员：

1. 不要被"50ms 超时"迷惑，真正的瓶颈可能不是速度，而是正确性
2. 优先保证语义正确，再考虑性能优化
3. 善用已有的详细日志，它们是最宝贵的调试资源

最后提醒：所有临时调试打印必须在最终提交前删除！