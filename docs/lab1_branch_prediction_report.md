# 实验 1：动态分支预测实验报告

## 1. 分支预测器设计

本实验在五级流水 Core 中接入了一个基于 BTB 和 BHT 的动态分支预测器，核心代码位于 `src/project/submit/BranchPrediction.sv` 和 `src/project/submit/Core.sv`。整体思路：IF 阶段用当前 `pc` 查表，提前给出是否跳转以及预测目标地址；EXE 阶段拿真实结果做校验，同时更新表项；一旦发现误预测，就通过 `flush` 和 `pc_redirect` 清空错误路径并重定向 PC。

`BranchPrediction.sv` 中把 BTB 和 BHT 合并成了一张直接映射表，每个表项包含 `tag`、`target`、`state` 和 `valid`。当前配置是 `DEPTH = 32`、`STATE_NUM = 2`，也就是 32 项表配合 2-bit 饱和计数器。索引使用 PC 的低位，高位作为 tag，因此查询开销小，但不同分支可能发生索引冲突。

IF 阶段的预测逻辑很简单：只有 `valid` 有效且 `tag` 匹配时才算命中，命中后再根据状态位最高位判断 taken 或 not taken。命中时使用表中保存的 `target` 作为预测目标，未命中时默认走 `pc + 4`。这一结果在 Core 中通过下面这条语句直接决定下一拍取值地址：

```sv
assign pc_pred_if = jump_pred_if ? pc_target_if : pc_plus4;
```

因此当前实现并不是等分支执行完再改 PC，而是在 IF 阶段就沿预测路径取指。PC 更新时仍保留优先级控制，`switch_mode` 和 `flush` 的优先级高于正常预测路径，遇到 `stall`、`mem_stall` 或 `csr_raw_hazard` 时则保持 PC 不变。

EXE 阶段负责给出真实跳转结果并训练预测器。Core 会把 `IDEXE_reg.pc`、`alu_res` 和 `branch_taken_exe` 送回 `BranchPrediction`，由 `next_state()` 对状态位做饱和更新。实际 taken 时状态向强跳转方向推进，实际 not taken 时状态向不跳方向回退；如果该分支此前没有命中表项，就从初始状态开始训练。为了让 EXE 阶段能够准确比较“当时是怎么预测的”，Core 还额外锁存了 `if_req_pc`、`if_req_pred_taken` 和 `if_req_pred_target`，并将这组预测信息继续传到 `ifid_pred_*` 和 `idexe_pred_*`。

误预测判断同样放在 EXE 阶段完成。当前实现既检查方向是否错误，也检查预测目标是否错误；只要有一项不一致，就置位 `mispredict_exe`，随后拉高 `flush`，将 PC 重定向到真实 `next_pc`，同时清空流水线中已经进入的错误路径指令。需要注意的是，这版代码里 `jal`、`jalr` 和条件分支都会参与真实跳转判断与纠错，但真正训练 BTB/BHT 的只有 `branch` 条件分支，因此预测器的主要覆盖对象仍然是条件分支。

---

## 2. 实验结果展示
当前实现已经能够通过 `verilate_sort` 完成排序测试，说明分支预测器已经正确接入取指、执行和恢复路径。测试中可以看到排序前后的数组输出符合预期，表明 BTB/BHT 的查询、更新以及误预测恢复逻辑都已经能够正常工作。

<img src="./image/屏幕截图 2026-03-19 190909.png" alt="排序测试结果 1" width="900" />

<img src="./image/屏幕截图 2026-03-19 191108.png" alt="排序测试结果 2" width="900" />


## 3. 思考题


### 3.1 思考题 1

题目要求：在报告里分析排序测试中分支预测成功和预测失败时的相关波形。

#### 3.1.1 波形截图

下图给出了排序测试中的两段波形。第一张用于说明分支预测失败后的恢复过程，第二张用于说明分支预测成功后的正常执行过程。

<img src="./image/屏幕截图 2026-03-19 201210.png" alt="思考题一波形 1" width="1000" />

<img src="./image/屏幕截图 2026-03-19 201926.png" alt="思考题一波形 2" width="1000" />



#### 预测失败的波形

1. 在 IF 阶段，当前 PC 进入 `BranchPrediction` 模块查表。若该分支在 BTB 中未命中，或者命中了但 `state` 的最高位为 0，则 `jump_pred_if = 0`，此时 Core 会按照 `pc + 4` 继续取指。
2. 取指请求发出时，Core 会把这次请求对应的预测信息锁存到 `if_req_pred_taken` 和 `if_req_pred_target` 中，之后继续经由 `ifid_pred_*` 和 `idexe_pred_*` 向 EXE 阶段传递。这样 EXE 阶段看到的是“这条指令在 IF 时到底是怎么被预测的”，而不是当前拍新的预测结果。
3. 当该分支进入 EXE 阶段后，ALU 和比较逻辑会给出真实结果。若真实结果是跳转，即 `branch_taken_exe = 1`，但之前预测值 `idexe_pred_taken = 0`，则说明方向预测错误。
4. 此时 `mispredict_exe` 变为 1，`flush` 也随之置 1，PC 更新优先级切换到 `pc_redirect`，流水线会丢弃 IF/ID 和 ID/EXE 中已经沿错误路径进入的年轻指令。
5. 若错误路径的取指请求已经发出但回复尚未返回，`if_drop_reply` 会把这次旧回复丢弃，避免错误路径指令重新进入流水线。
6. 同一拍或下一拍中，预测器还会根据 EXE 的真实结果更新表项，写入新的 `tag`、`target` 和 `state`。如果这是第一次遇到该分支，状态通常从 `00` 开始训练；如果该分支之后继续多次 taken，则其状态会逐步从弱不跳转转为弱跳转、强跳转。




#### 预测成功时的波形

1. 在 IF 阶段，当前分支命中 BTB，且对应状态位已经进入“预测跳转”的区域，因此 `jump_pred_if = 1`，`pc_target_if` 直接作为下一拍的取指地址。
2. 这一次预测结果同样会被锁存到 `if_req_pred_taken / if_req_pred_target`，随后经由 `ifid_pred_*` 和 `idexe_pred_*` 传到 EXE 阶段。
3. 当该分支真正到达 EXE 阶段时，真实结果满足 `branch_taken_exe = 1`，并且真实目标地址 `alu_res` 与当时预测的 `idexe_pred_target` 一致。
4. 因为方向和目标都正确，`mispredict_exe = 0`，所以 `flush = 0`。此时流水线不会清空，前面已经沿预测路径取到的指令可以继续执行。
5. 虽然没有触发恢复，但预测器仍然会在 EXE 阶段根据真实结果继续更新状态位。对于循环中大量重复出现、且大多数时间 taken 的条件分支，状态机会逐步收敛到强跳转状态，因此后续多次预测都能够命中。

从性能角度看，预测成功波形体现了动态分支预测的核心优点：分支指令不需要等到 EXE 阶段才决定下一条 PC，而是在 IF 阶段就提前沿正确路径取指，因此减少了流水线停顿和清空次数。



### 3.2 思考题 2

题目要求：分析并呈现自己的 Core 中 `pc` 相关更新逻辑。

<!-- #### PC 相关信号

在当前 `Core.sv` 中，与 PC 更新直接相关的核心信号有：

- `pc`：当前 IF 阶段使用的取指地址
- `pc_plus4`：顺序执行时的下一条地址
- `pc_pred_if`：IF 阶段根据预测器得到的预测下一条地址
- `next_pc`：EXE 阶段根据真实执行结果得到的下一条地址
- `pc_redirect`：误预测时用于重定向 PC 的真实地址
- `flush`：误预测恢复信号
- `stall / mem_stall / csr_raw_hazard`：暂停 PC 前进的保持信号 -->



#### PC 更新优先级

当前实现中，PC 寄存器的更新逻辑如下：

```sv
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        pc <= 64'h0000_0000;
    end else if (switch_mode) begin
        pc <= pc_csr;
    end else if (flush) begin
        pc <= pc_redirect;
    end else if (stall || mem_stall || csr_raw_hazard) begin
        pc <= pc;
    end else begin
        pc <= pc_pred_if;
    end
end
```

从这个 always 块可以直接看出，PC 更新的优先级为：

1. 复位后，PC 初始化为 `0`
2. 如果发生异常返回、陷入或特权级切换，则 `switch_mode` 优先，PC 跳转到 `pc_csr`
3. 如果 EXE 阶段检测到误预测，则 `flush` 生效，PC 被重定向到 `pc_redirect`
4. 如果存在数据相关、访存等待或 CSR RAW hazard，则 PC 保持不变
5. 只有在上述情况都不存在时，PC 才会采用 IF 阶段预测得到的 `pc_pred_if`



```text
当前 pc
-> IF 查询 BranchPrediction
-> 生成 pc_pred_if
-> 若无异常/误预测/停顿，则下一拍 pc = pc_pred_if
-> 指令返回后，将 if_req_pc 写入 IFID_reg.pc
-> 指令进入 EXE 后计算真实 branch_taken_exe 和 next_pc
-> 若发现误预测，则 flush=1，下一拍 pc = pc_redirect
```



### 3.3 思考题 3

题目要求：修改分支预测器中状态预测的比特数，比如从 2 比特改为 1 比特或者 3 比特，计算分支预测成功率，并分析状态比特数与成功率之间的关系。

#### 3.3.1 修改位置与思路

本实验中状态位宽由 `BranchPrediction.sv` 中的参数 `STATE_NUM` 控制：

```sv
module BranchPrediction #(
    parameter DEPTH      = 32,
    parameter ADDR_WIDTH = 64,
    parameter STATE_NUM  = 2
) (
```

预测逻辑和状态更新逻辑本身已经参数化，因此在本实现中，测试 1-bit、2-bit、3-bit 预测器时，核心修改点就是改变 `STATE_NUM` 的取值。

状态预测使用最高位作为 taken / not taken 的分界：

```sv
assign jump_pred_if = hit_if && btb_if.state[STATE_NUM-1];
```

因此：

 当 `STATE_NUM = 1` 时，`state=0` 预测不跳，`state=1` 预测跳转
 当 `STATE_NUM = 2` 时，`00/01` 预测不跳，`10/11` 预测跳转
 当 `STATE_NUM = 3` 时，`000~011` 预测不跳，`100~111` 预测跳转

状态更新函数同样已经写成了通用形式：

```sv
function automatic state_t next_state(
    input state_t cur_state,
    input logic   taken
);
    state_t state_next;
    begin
        state_next = cur_state;
        if (taken) begin
            if (state_next != state_t'({STATE_NUM{1'b1}})) begin
                state_next = state_next + state_t'(1);
            end
        end else if (state_next != state_t'('0)) begin
            state_next = state_next - state_t'(1);
        end
        return state_next;
    end
endfunction
```

所以当状态位数从 2 改成 1 或 3 时，不需要额外重写状态机，只需要修改参数即可完成实验。

#### 3.3.2 成功率统计

本实验在 `verilate_sort` 测试中统计成功率。为了只统计“条件分支预测器”本身的效果，统计时采用“高脉冲个数”作为计数口径，而不是统计信号持续高电平的拍数。具体而言：

 总预测次数：`pred_branch_exe` 的高脉冲个数
 预测失败次数：`pred_branch_exe && mispredict_exe` 的高脉冲个数

之所以不直接用 `branch_inst_exe`，是因为在当前 `Core.sv` 中：

```sv
assign branch_inst_exe = IDEXE_reg.valid && IDEXE_reg.npc_sel;
assign pred_branch_exe = IDEXE_reg.valid && (IDEXE_reg.inst[6:0] == BRANCH_OPCODE);
```

其中 `branch_inst_exe` 同时覆盖 `jal / jalr / branch`，而当前 BTB/BHT 的训练重点只在 `branch` 上。因此思考题三更合理的统计口径应当是条件分支本身，也就是 `pred_branch_exe`。

成功率公式为：

$$
\text{Success Rate} = \frac{\text{Total} - \text{Mispredict}}{\text{Total}}
$$

#### 3.3.3 实验结果

在相同的 `verilate_sort` 测试下，对三种状态位宽分别进行统计，得到结果如下：

<img src="./image/屏幕截图 2026-03-20 165211.png" alt="思考题三 1" width="1000" />
<img src="./image/屏幕截图 2026-03-20 171644.png" alt="思考题三 1" width="1000" />
<img src="./image/屏幕截图 2026-03-20 171616.png" alt="思考题三 1" width="1000" />
<img src="./image/屏幕截图 2026-03-20 171359.png" alt="思考题三 1" width="1000" />
<img src="./image/屏幕截图 2026-03-20 171851.png" alt="思考题三 1" width="1000" />
<img src="./image/屏幕截图 2026-03-20 171924.png" alt="思考题三 1" width="1000" />

| 状态位数 | 总预测次数 | 预测失败次数 | 预测成功率 |
| --- | ---: | ---: | ---: |
| 1-bit | 3586 | 1087 | 69.69% |
| 2-bit | 3586 | 859 | 76.05% |
| 3-bit | 3586 | 866 | 75.85% |

可以看到：

 1-bit 成功率最低
 2-bit 成功率最高
 3-bit 与 2-bit 接近，但略低于 2-bit

#### 结果分析

1-bit 预测器的主要问题是“状态翻转过于敏感”。在 1-bit 情况下，只要最后一次循环退出发生 not taken，预测状态就会立刻翻转；下次再次进入该循环时，前几次又容易预测错误。因此 1-bit 对短时扰动不够稳定，容易在循环边界处反复犯错。

2-bit 饱和计数器引入了迟滞效应。一次偶然的 not taken 不会立刻把状态从“强跳转”翻到“预测不跳”，这使得它非常适合处理排序测试中大量“多数 taken、少数 not taken”的循环分支模式。因此 2-bit 通常能取得比 1-bit 更高的成功率。

3-bit 预测器虽然也有更强的迟滞效应，但状态更多，冷启动训练更慢；当分支行为发生变化时，也需要更多次真实结果才能把状态拉回另一侧。在当前排序测试中，程序中的条件分支并不是长期完全固定不变的，因此过强的迟滞并没有继续提升成功率，反而略低于 2-bit。


### 3.4 思考题 4

题目要求：分析间接跳转场景下 BTB 对 `ret` 指令预测的局限性，并说明 Return Address Stack 的工作原理、优势与限制。

#### 3.4.1 `ret` 在 BTB 中对应几个表项

题目给出的程序中，三次调用都进入同一个函数 `foo`，而真正执行返回的是函数末尾的同一条指令：

```asm
0x500: JALR x0, x1, 0   # ret
```

如果只使用 BTB 进行预测，那么 BTB 的索引依据是“当前跳转指令自身的 PC”，也就是 `ret` 这条指令的地址 `0x500`。因此：

 对 BTB 而言，这三次返回对应的是同一条静态指令
 所以它在 BTB 中只对应一个表项，而不是三个表项

BTB 里记录的是：

```text
跳转指令 PC -> 预测目标地址
```

对于 `ret` 来说，左边的 PC 始终是 `0x500`，不会因为调用点不同而变化；变化的是右边的真实返回地址。

#### 3.4.2 A→B→C 顺序调用时每次 `ret` 的预测结果

三次调用的真实返回地址分别是：

 call site A：返回到 `0x104`
 call site B：返回到 `0x204`
 call site C：返回到 `0x304`

如果程序按 A→B→C 的顺序依次调用 `foo`，而 BTB 中只有一项对应 `ret@0x500`，则预测过程如下。

第一次执行 `ret`（来自 A）：

 这是第一次遇到 `ret@0x500`
 BTB 中通常还没有该表项
 因此预测结果是 miss，无法正确给出返回目标
 真实返回地址是 `0x104`
 本次执行后，BTB 会把 `ret@0x500` 的目标更新为 `0x104`

第二次执行 `ret`（来自 B）：

 此时 BTB 已经有 `ret@0x500` 这项
 BTB 会预测目标为上一次记录的 `0x104`
 但这次真实返回地址是 `0x204`
 因此预测错误
 执行后 BTB 又会把目标覆盖为 `0x204`

第三次执行 `ret`（来自 C）：

 此时 BTB 对 `ret@0x500` 的预测目标变成 `0x204`
 但真实返回地址是 `0x304`
 因此仍然预测错误
 执行后 BTB 又会被更新为 `0x304`


因此，在冷启动条件下，这三次 `ret` 的 BTB 预测准确率为：

$$
0 / 3 = 0\%
$$


#### 为什么 BTB 对 `ret` 存在结构性局限

对于直接跳转指令，例如：

```asm
JAL x1, foo
```

它的目标地址由指令本身的立即数直接决定。也就是说：

 给定某一条 `jal` 指令的 PC
 它的跳转目标基本是固定的

因此 BTB 很适合这类情况，因为它隐含的假设是：

```text
同一条静态跳转指令 PC -> 大多数时候对应同一个目标地址
```

但 `ret` 并不是直接跳转，而是间接跳转：

```asm
JALR x0, x1, 0
```

它的目标地址并不编码在指令里，而是来自寄存器 `x1` 的当前值。`x1` 保存的是调用者的返回地址，所以：

 从 A 调用时，`x1 = 0x104`
 从 B 调用时，`x1 = 0x204`
 从 C 调用时，`x1 = 0x304`

虽然执行的都是同一条 `ret@0x500`，但真实目标却随调用上下文变化。

因此，BTB 对 `ret` 的结构性局限在于：

 BTB 是“按跳转指令 PC 建立单目标映射”的结构
 `ret` 的真实目标却是“同一条指令 PC 对应多个可能目标”

其根本原因是：

```text
ret 的目标是上下文相关的动态值，而 BTB 只记录与指令 PC 相关的静态目标。
```


#### 3.4.4 Return Address Stack 的工作原理

为了解决 `ret` 预测问题，工业界通常引入 Return Address Stack，简称 RAS。

RAS 的核心思想不是记“ret 指令以前跳到哪”，而是记“最近还没有返回的调用点是谁”。它本质上是一小块硬件栈，遵循后进先出原则。

其工作方式如下：

1. 遇到函数调用指令时执行 push

当处理类似下面的调用指令时：

```asm
JAL  x1, foo
JALR x1, rs, imm
```

硬件会把“返回地址”压入 RAS。这个返回地址通常是当前调用指令的 `PC + 4`。

例如：

 A 调用 `foo` 时，把 `0x104` 压栈
 B 调用 `foo` 时，把 `0x204` 压栈
 C 调用 `foo` 时，把 `0x304` 压栈

2. 遇到 `ret` 时执行 pop

当检测到：

```asm
JALR x0, x1, 0
```

这种典型返回形式时，硬件会从 RAS 栈顶弹出一个地址，并把它作为 `ret` 的预测目标。

由于函数调用和返回通常满足严格的嵌套关系，最近一次未返回的调用点正好就是当前应该返回的位置，因此这个预测天然符合函数调用语义。

#### RAS 相比 BTB 预测 `ret` 的优势

RAS 的优势在于它记录的是“调用历史栈”，而不是“同一条 ret 曾经去过哪里”。

如果存在多层嵌套调用，例如：

```text
A 调 foo -> push 0x104
foo 内再从 B 调 foo -> push 0x204
foo 内再从 C 调 foo -> push 0x304
```

那么之后连续执行返回时：

 第一次 `ret` 取出栈顶 `0x304`
 第二次 `ret` 取出 `0x204`
 第三次 `ret` 取出 `0x104`

这个顺序与真实程序返回顺序完全一致，而 BTB 做不到这一点。

因此，RAS 相比 BTB 预测 `ret` 的主要优势有：

 它利用了调用/返回天然的后进先出结构
 能区分同一条 `ret` 在不同调用上下文下的不同目标
 对递归调用和多层嵌套调用尤其有效
 不会像 BTB 那样被“上一轮返回地址”简单覆盖污染

####  RAS 自身的局限性

RAS 虽然适合 `ret`，但也不是没有限制。

1. 它只对规范的调用-返回结构效果最好  

2. 它有深度限制  
RAS 通常只是一个很小的硬件栈，深度有限。如果函数嵌套过深，就会发生栈溢出；如果出现异常返回路径，也可能出现下溢。

3. 它需要处理投机执行带来的恢复问题  
现代流水线会在预测路径上提前执行 push/pop。如果后续发现分支预测错误或流水线 flush，就需要把 RAS 的状态一起恢复，否则栈内容会被污染。

4. 它不能替代普通 BTB  
RAS 只擅长处理 `ret` 这类返回指令；对于普通直接跳转、条件分支、一般间接跳转，仍然需要 BTB 或其他预测结构配合。
