# Lab2 Cache 实验说明、实现拆解与调试复盘

这份文档的目标不是简单记录“我改了哪些文件”，而是把这次 Lab2 真正要理解的东西讲透。你看完之后，应该能回答三类问题：

1. 这个实验到底要做什么，为什么不只是“补一个 Cache.sv”那么简单。
2. `CacheBank.sv`、`Cache.sv`、`Dcache.sv`、`Core.sv` 分别承担什么职责，代码应该按什么顺序写。
3. 我这次 debug 时到底遇到了什么问题，为什么会出现这些问题，最后又是怎么修好的。

本文默认你已经能读懂基本的五级流水、AXI/ready-valid 握手、RISC-V load/store/CSR/异常返回的基本语义。

---

## 1. 这次实验到底要完成什么

根据实验文档 `docs/lab2.md`，Lab2 的核心目标有三件事：

1. 理解并接入 Cache。
2. 通过 `make verilate_sort`。
3. 跑通 `make kernel`，并且至少看到线程切换。

所以这个实验不是单纯的“把 miss 处理做出来”。

真正困难的是：**Cache 会改变整个 CPU 的时序假设**。

在没有 Cache 的版本里，取指和访存通常都会走一个显式的总线状态机，流水线天然“比较慢”，很多本来就存在的问题会被慢时序掩盖掉。  
一旦接入 I-Cache / D-Cache，命中时 CPU 可能一拍一条指令，很多老问题就会暴露出来，例如：

- forwarding 不完整
- load-use hazard 处理不严谨
- CSR hazard 没有考虑
- flush / stall 优先级不对
- invalid bubble 还带着旧控制信号往后跑
- MMIO 等待响应时重复发请求

所以，**Lab2 的本质是“缓存 + 流水线 + 总线 + 异常/CSR”联合调试**。

---

## 2. 先建立整体结构

从系统角度看，我这次代码的整体关系可以先粗略理解成下面这样：

```text
                +--------------------+
IF: PC -------->| Icache             |
                |  内部再调用 Cache  |
                +---------+----------+
                          |
                          v
                    imem Mem2Axi
                          |
                          v
                         AXI


                +--------------------+
MEM: addr/data -> Dcache             |
                |  1. 普通内存走 Cache |
                |  2. MMIO 直接旁路   |
                |  3. store miss 特判 |
                +---------+----------+
                          |
                          v
                    dmem Mem2Axi
                          |
                          v
                         AXI
```

而 `Cache` 内部又可以继续拆成：

```text
                +----------------------+
CPU req ------->| CacheBank            |
                |  hit/miss/tag/data   |
                |  valid/dirty/lru     |
                +----+-------------+---+
                     |             |
                     | miss        | victim line
                     v             v
                +---------+   +------------------+
                | CMU     |   | WriteBackBuffer  |
                | READ    |   | 暂存被替换脏行   |
                | WRITE   |   +------------------+
                +----+----+
                     |
                     v
                   Memory
```

所以从代码职责上看：

- `CacheBank.sv` 负责“存什么、命中没命中、替换哪一路”
- `Cache.sv` 负责“miss 之后怎么和内存交互”
- `Icache.sv` 负责把取指请求包装成 Cache 可接受的读请求
- `Dcache.sv` 负责把 load/store 包装成 Cache 请求，并处理 MMIO 旁路
- `Core.sv` 负责在流水线里正确消费 `hit`、正确停顿、正确 flush、正确提交

这五层都要同时正确，实验才真正算做完。

---

## 3. `CacheBank.sv` 应该怎么理解

这是本实验最值得先吃透的模块，因为它定义了“缓存行到底长什么样、命中到底怎么判断”。

### 3.1 地址是怎么切开的

在 `CacheBank.sv` 里，地址被切成四段：

```text
| tag | index | offset | byte |
```

含义分别是：

- `byte`：64 位字里的字节偏移
- `offset`：一个 cache line 里第几个 64 位 word
- `index`：访问哪一组
- `tag`：这一行属于哪段高地址

这里每条 cache line 有 `BANK_NUM=4` 个 64 位 word，所以一行是 256 bit。

### 3.2 这个 CacheBank 存了什么

它本质上维护了 5 组二维数组：

```text
valid_arr[way][index]
dirty_arr[way][index]
lru_arr[way][index]
tag_arr[way][index]
data_arr[way][index]
```

也就是对每个 `way/index` 位置，保存：

- 这行是否有效
- 这行是否被写脏
- 最近使用信息
- 这行对应的 tag
- 这行真正的数据

### 3.3 命中是怎么判断的

判断非常直接：

```text
way0 hit = tag 相等 && valid=1
way1 hit = tag 相等 && valid=1
hit_cpu  = hit0 || hit1
```

命中了以后，再根据 `offset_cpu` 从整条 line 里取出当前 64 位 word。

### 3.4 写命中是怎么做的

写命中并不会立刻写内存，而是：

1. 在命中的那一路里，按 `wmask` 改写对应字节。
2. 同时把 `dirty` 位置 1。

这就是典型的 **write back**。

好处是：

- 写命中很快
- 不需要每次 store 都下总线

代价是：

- 当这一行以后被替换掉时，必须把脏数据写回内存

### 3.5 替换路是怎么选的

代码里：

```sv
assign set_cache = lru_arr[0][index_cpu];
```

这意味着 `lru_arr` 的编码方式不是“直接存 victim”，而是“记录谁最近被使用过”。  
结合后面的更新逻辑：

- 如果 way0 命中，就把 `lru_arr[0]=1, lru_arr[1]=0`
- 如果 way1 命中，就把 `lru_arr[0]=0, lru_arr[1]=1`

因此 `set_cache` 实际上表达的是：

- 如果最近用的是 way0，那么下一次替换 way1
- 如果最近用的是 way1，那么下一次替换 way0

这就是二路组相联里最简单的一种 LRU 近似编码。

### 3.6 miss 时 CacheBank 做什么，不做什么

CacheBank 在 miss 时只负责：

- 告诉外部 `miss_cache=1`
- 给出 miss 行首地址 `addr_cache`
- 给出需要替换的 way `set_cache`
- 如果 victim 是脏的，再给出 `addr_wb` 和 `data_wb`

它**不负责**自己去读内存，也不负责自己去写回内存。  
这些动作都交给 `Cache.sv` 里的 CMU。

这点非常关键：**CacheBank 负责“状态与存储”，CMU 负责“事务与控制”**。

---

## 4. `Cache.sv` 的本质：给 CacheBank 配一个 miss 控制器

如果只有 `CacheBank`，那么 Cache 只会“发现 miss”，不会“解决 miss”。  
所以 `Cache.sv` 的核心就是补齐一个 CMU 状态机。

### 4.1 为什么需要单独的 CMU

一条 cache line 是 256 bit，但内存接口一次只传 64 bit。  
所以一次 refill 不是“一拍拿回来”，而是：

1. 先读第 0 个 beat
2. 再读第 1 个 beat
3. 再读第 2 个 beat
4. 再读第 3 个 beat

写回脏行也是同理，要四拍写出去。

这天然就是一个状态机问题。

### 4.2 这次实现的三个状态

`Cache.sv` 里我保留的是三个状态：

- `CMU_IDLE`
- `CMU_READ`
- `CMU_WRITE`

含义分别是：

- `IDLE`：空闲，没有 miss 正在处理
- `READ`：正在给 miss 行做 refill
- `WRITE`：正在把 write-back buffer 里的脏行写回内存

### 4.3 read miss 的完整流程

一次典型 read miss 的时序可以理解成：

```text
CPU miss
  -> CacheBank 拉高 miss_cache
  -> CMU 记录 refill_base_addr 和 victim way
  -> 进入 CMU_READ
  -> 逐 beat 发读请求
  -> 每收到一个 beat，就通过 wen_rd 写进 CacheBank
  -> 最后一个 beat 到达，finish_rd=1
  -> 如果 write-back buffer 还有脏行要写，转去 CMU_WRITE
  -> 否则回到 IDLE
```

这里最关键的几个信号是：

- `beat_count`：当前是第几个 beat
- `read_req_fire`：读请求真正发出
- `read_resp_fire`：一个返回 beat 真正被接收
- `wen_rd`：把这个 beat 写进 CacheBank
- `finish_rd`：最后一个 beat 写完

### 4.4 为什么代码里还要区分 `*_req_fire`、`*_resp_now`、`*_resp_fire`

这是本次实现里一个很容易忽视，但非常重要的点。

因为总线可能出现两种情况：

1. 请求发出后，响应晚几拍回来
2. 请求和响应同拍就完成

如果你只写“发请求”和“等响应”两段粗糙逻辑，很容易在第二种情况下重复计数或者漏计数。  
所以我在 `Cache.sv` 里显式区分了：

- `read_req_fire`
- `read_resp_now`
- `read_resp_fire`

写通道也一样有：

- `write_req_fire`
- `write_resp_now`
- `write_resp_fire`

这套写法的意义是：**不把“请求 accepted”误当成“响应返回”，也不把“同拍完成”漏掉**。

这类 ready-valid 细节，是 Cache CMU 代码最容易出 bug 的地方。

### 4.5 write back buffer 为什么必要

如果没有 write-back buffer，那么 miss 遇到脏 victim 时，流程会变成：

1. 先完整写回旧行
2. 再完整读入新行

流水线会被这两段都卡住。

而有了 write-back buffer 之后，流程变成：

1. 先把 victim line 拷进 buffer
2. 立刻优先读 miss 的新行
3. 流水线在 refill 结束后就能继续
4. 旧行什么时候写回，由 CMU 后面慢慢做

这就是实验文档里说的 **read priority**。

---

## 5. `Icache.sv` 和 `Dcache.sv` 不是“顺手封一下”，而是系统边界

### 5.1 `Icache.sv` 很纯粹

`Icache.sv` 的事非常单纯：

- 上层输入是 `pc`
- 下层内部调用 `Cache`
- 如果命中，就从一条 64 位数据里根据 `pc[2]` 选高 32 位还是低 32 位，输出指令

I-Cache 基本上只有“读”。

### 5.2 `Dcache.sv` 是真正复杂的那个包装层

`Dcache.sv` 要处理三种完全不同的请求：

1. **普通可缓存内存访问**
2. **MMIO 访问**
3. **store miss 的特殊优化路径**

所以 D-Cache 不是简单把 `Cache` 套一下就结束了。

### 5.3 为什么 MMIO 不能进 Cache

因为像 `mtime`、`mtimecmp`、`uart` 这类地址不是普通 RAM。

如果你把这些地址缓存起来，会出现：

- 读到旧的 timer 值
- 重复写 UART
- 软件看到的外设行为不真实

因此在 `Dcache.sv` 里必须先做地址判定：

- DDR / ROM / buffer：可以走 Cache
- UART / CONV / MISC：直接旁路到总线

### 5.4 这次修掉的第一个典型 bug：MMIO 重发

这是一个很有代表性的 bug。

#### 现象

`sort` 的输出在尾部出现重复打印，看起来像是程序本身重复执行了打印代码。

#### 我是怎么发现的

我先对比了两件事：

1. 指令流有没有真的重复回到那段打印代码。
2. UART 输出是不是比程序真实执行次数更多。

结果发现：**程序没有真的重复执行那段逻辑，但外设输出重复了**。  
这就说明问题不在控制流，而在 MMIO 写请求本身。

#### 根因

等待 MMIO 写响应的那几拍里，Dcache 还在重复把同一个写请求发出去。  
对 UART 来说，这就等于把同一个字符写了很多次。

#### 修法

在 `Dcache.sv` 里加入：

- `mmio_pending`
- `mmio_read_pending`
- `mmio_write_pending`
- `mmio_addr_q`
- `mmio_wdata_q`
- `mmio_wmask_q`

也就是：

1. 请求一旦发出去但响应还没回来，就把它锁存下来
2. 在 pending 期间，不允许再重复接受同一笔新 MMIO 请求
3. 等响应回来再清 pending

#### 启发

**只要一个请求会跨拍存在，你就必须给它“在途状态”。**  
否则就会出现“上层以为自己只发了一次，下层其实收到了很多次”的问题。

---

## 6. 这次最重要的部分：`Core.sv` 怎么和 Cache 正确耦合

很多同学会觉得 Cache 做完之后，接到 Core 里只是“改一下线”。  
实际上不是，真正难点恰恰在 `Core.sv`。

### 6.1 IF 不再直接等总线，而是等 I-Cache 是否命中

现在取指不再是：

```text
PC -> 总线 -> 指令
```

而是：

```text
PC -> Icache
   命中：直接拿到 inst
   失配：Icache 去内存 refill
```

所以 IF 级的新停顿条件变成：

- `if_stall = ~hit_icache`

命中就继续，不命中就等。

### 6.2 MEM 级的新停顿条件

MEM 级同理：

```sv
assign mem_stall = EXEMEM_reg.valid &&
                   (EXEMEM_reg.re_mem || EXEMEM_reg.we_mem) &&
                   !hit_dcache;
```

也就是说：

- 只要有真实 load/store 在 MEM
- 且这笔访问还没“完成”
- 就要卡住流水线

这里的 `hit_dcache` 对 Core 而言其实更接近“这拍访存是否完成”，不一定严格等价于“Cache hit”。  
例如 MMIO 响应返回时，`Dcache.sv` 也会把 `hit_cpu` 拉高，让 Core 认为这笔访存已经结束。

### 6.3 接入 Cache 之后，forwarding 必须更完整

以前总线很慢的时候，有些 RAW hazard 恰好被“自然拉开”了；现在命中 Cache 时一拍一条，很容易暴露 forwarding 不完整的问题。

这次我在 `Core.sv` 里重点补了三类东西：

1. `WB_SEL_PC` 的 forwarding
2. `WB_SEL_MEM` 的 forwarding
3. CSR 相关 forwarding / hazard

尤其 CSR 很容易被漏掉，因为它不是普通的整数 ALU 写回。

### 6.4 load-use 和 CSR hazard 必须单独处理

`load-use` 依旧要 stall，因为 load 的数据到得更晚。  
另外 CSR 也要额外处理 RAW hazard：

```sv
wire csr_raw_hazard = csr_ren_id && (
    (IDEXE_reg.valid && IDEXE_reg.we_csr && (IDEXE_reg.csr_addr == csr_addr_id)) ||
    (EXEMEM_reg.valid && EXEMEM_reg.we_csr && (EXEMEM_reg.csr_addr == csr_addr_id)) ||
    (MEMWB_reg.valid && MEMWB_reg.we_csr && (MEMWB_reg.csr_addr == csr_addr_id))
);
```

这段逻辑的意义是：  
如果 ID 正在读某个 CSR，而更老的指令还没把这个 CSR 写回，那么宁可停一下，也不要读到旧值。

---

## 7. 这次最有启发意义的几个 debug 案例

下面几件事，是我认为最值得学走的“基础”。

不是因为它们只对这次实验有用，而是因为它们以后做流水线、总线、Cache、MMU 都会反复遇到。

### 7.1 基础一：`flush` 和 `stall` 不是各写各的，它们其实在争“谁先级更高”

#### 现象

`kernel` 之前会在 `printf_core` 一带炸掉。  
更具体地说，是一条本该跳到 `0x80200874` 的跳转被“吃掉了”。

#### 我是怎么发现的

我没有一上来就盯 Cache，而是先盯**第一处架构级分歧**。  
然后在那个 PC 附近加很窄的流水线打印，只看：

- IFID / IDEXE / EXEMEM / MEMWB 里的 PC
- `flush`
- `mem_stall`

结果看到一个关键现象：

- 同一拍里 `flush=1`
- 同时 `mem_stall=1`

这意味着：

- 前级被清掉了
- 但真正携带跳转结果的那条指令因为 `mem_stall` 没能往后推进

于是跳转信息直接丢了。

#### 根因

以前写 `flush` 的时候默认假设“EX 判完跳转就能立即 redirect”。  
但现在前面还有 cache miss，流水线不一定真的能在这一拍完成状态推进。

#### 修法

把：

```sv
flush = mispredict_exe;
```

改成：

```sv
flush = mispredict_exe && !mem_stall;
```

也就是：**有更老的访存指令没走完时，先别急着 flush，等能安全推进时再 redirect。**

#### 启发

**控制流修正不是“看到 mispredict 就立刻清空”这么简单。**  
你必须保证产生 redirect 的那条指令，本拍确实能活着进入正确的下一级。

---

### 7.2 基础二：`valid` 位不是注释，它是流水线协议的一部分

这是这次最关键、也最值得记住的一个点。

#### 现象

`kernel` 之前会出现很奇怪的 CSR 失配：

- `mscratch` 会偶发写坏
- `mret` 会在不该提交的时候提交
- 最后炸成非常离谱的 PC，例如 DUT 跑到 `0x30`

#### 我是怎么发现的

我把打印范围缩到 trap / CSR 一带，重点看：

- `MEMWB_reg.valid`
- `MEMWB_reg.inst`
- `MEMWB_reg.we_csr`
- `MEMWB_reg.csr_ret`

然后发现一个决定性证据：

- 有些时候 `MEMWB_reg.valid=0`
- 但 `MEMWB_reg.inst` 里还留着旧的 `csrrw` / `mret`
- 同时 `we_csr` 或 `csr_ret` 也还保留着

也就是说：

**无效 bubble 并不“无害”**，它还带着旧的副作用控制位在往后跑。

#### 根因

在 `IDEXE/EXEMEM/MEMWB` 这些流水段里，以前很多控制位是直接搬过去的，没有和 `valid` 绑死。  
于是当某拍因为 miss / flush / trap 产生了 invalid bubble 时，这个 bubble 虽然 `valid=0`，但里面仍然可能带着旧的：

- `we_reg`
- `we_mem`
- `we_csr`
- `csr_ret`
- `inst`
- `rd`
- `csr_addr`

这会导致后级模块误以为它是一条真的指令。

#### 修法

我做了两层修复。

第一层，在流水线寄存器写入时把副作用控制位和 `valid` 强绑定，例如：

- `IDEXE_reg.we_reg <= IFID_reg.valid && we_reg_id`
- `EXEMEM_reg.we_csr <= IDEXE_reg.valid && IDEXE_reg.we_csr`
- `MEMWB_reg.we_reg <= EXEMEM_reg.valid && EXEMEM_reg.we_reg`

同时在 invalid 情况下把下面这些字段清零：

- `inst`
- `pc`
- `rd/rs`
- `wb_sel`
- `mem_op`
- `csr_addr`
- `csr_ret`

第二层，在 `Core.sv -> CSRModule` 接口处再加一道保险：

```sv
.csr_we_wb(MEMWB_reg.we_csr && MEMWB_reg.valid)
.csr_ret(MEMWB_reg.valid ? MEMWB_reg.csr_ret : 2'b0)
```

#### 启发

**一个 bubble 真正“无效”，必须做到两件事：**

1. `valid=0`
2. 所有会产生架构副作用的控制位也都必须等价于 0

只做第一件事，不做第二件事，早晚出大问题。

---

### 7.3 基础三：共享响应通道一定要有“归属者”

#### 现象

在 D-Cache 里，写通道一开始混着承载三种东西：

- Cache 自己的 write back
- MMIO 写
- store miss 的直写

如果不显式区分“当前谁拥有写响应通道”，就很容易出现：

- A 发的请求，B 把响应吃了
- 一个事务还没结束，另一个事务就插进来

#### 我是怎么发现的

我在调 store miss 直写的时候发现，很多 bug 不是单纯的“慢”，而像是：

- 状态一直 pending
- 明明有 `wvalid_in`，但不清 pending
- 或者另一路事务被莫名其妙地提前完成

这通常说明：**响应来了，但代码不知道它属于谁。**

#### 修法

在 `Dcache.sv` 里增加：

```text
WRITE_OWNER_NONE
WRITE_OWNER_CACHE
WRITE_OWNER_STORE_MISS
WRITE_OWNER_MMIO
```

也就是加一个显式的 `write_owner_q` 状态机，要求：

- 谁先成功发出写请求，谁就拿到 owner
- 在 owner 清掉之前，别的写事务不能插进来
- 收到 `wvalid_in` 时，只允许 owner 对应的那一路消费它

#### 启发

**只要多个来源共享同一条“无标签响应通道”，就必须在本地自己维护 owner。**  
这和 Cache 无关，做 AXI bridge、TLB miss queue、MMU page walker 时都会遇到。

---

### 7.4 基础四：看到 timeout，先别急着说“只是性能差”

这是这次调 Cache 时很重要的一条经验。

一开始 `kernel` 超时很容易让人误判成：

> “就是 cache 还不够快。”

但后面我真正定位后发现，很多“超时”其实对应的是：

- 活锁
- 响应归属错误
- stale line
- invalid bubble 提交错误

也就是说，**超时不一定是性能问题，可能是正确性问题伪装成了性能问题。**

#### 我是怎么做区分的

我没有只看“跑了多久”，而是看：

1. 第一处架构分歧发生在哪
2. 是同一条 PC 一直在重试，还是程序真的在持续前进
3. 是某个地址总读错，还是所有地方都慢

比如后面我观察到 `task_init()` 里某个 `ld a5, 0(s1)` 一直重试，就知道那不是“普通地慢一点”，而是状态根本没推进。

#### 启发

**如果你只盯着“时间上限到了”，你很容易把死锁、活锁、错误提交，全都误判成性能差。**  
调 Cache 一定要同时看“有没有前进”和“前进得对不对”。

---

## 8. 结合这次代码，怎么自己从头把它写出来

如果让我重新做一遍，而且目标是“稳定地做出来”，我会按下面顺序写。

### 第一步：先只吃透 `CacheBank.sv`

先完全弄明白：

- tag/index/offset 怎么切
- hit 怎么算
- data line 怎么取 word
- write hit 怎么按字节更新
- dirty / valid / lru 怎么更新
- miss 时应该向外给什么信息

如果这一步没吃透，后面 CMU 和 Dcache 包装层会越写越乱。

### 第二步：在 `Cache.sv` 里只做最朴素的 CMU

先别急着优化，先让下面三件事正确：

1. miss 能进入 `READ`
2. refill 的 4 个 beat 能正确写回 `CacheBank`
3. 脏行能通过 `WRITE` 状态写回内存

这时候即使性能一般，也已经是一个正确的 Cache。

### 第三步：接 `Icache.sv`

I-Cache 比 D-Cache 简单得多，适合先打通。

你只需要保证：

- 命中时能立刻给出当前 PC 对应的指令
- 失配时能正确请求 line refill
- `hit_icache` 能让 IF 级按预期停住

### 第四步：接 `Dcache.sv`

这一步要先做“正确版本”，再考虑优化：

1. 先分清普通内存和 MMIO
2. MMIO 必须旁路，不得进 Cache
3. 先把 load/store 的基本 hit/miss 跑通

### 第五步：最后才去修 `Core.sv`

这里是大头。

要系统性检查：

- IF stall
- MEM stall
- load-use
- forwarding
- CSR RAW hazard
- flush / stall / switch_mode 优先级
- exception 提交拍对齐
- invalid bubble 是否真的无副作用

如果你一开始就盲改 `Core.sv`，但没有先把 Cache 行为说清楚，后面会很难区分“到底是 Cache 错了，还是流水线错了”。

---

## 9. 思考题 1：用文字和结构图说明 `CacheBank` 的工作原理

这是我建议直接写进报告的版本。

### 9.1 结构图

```text
CPU 地址
  |
  +--> tag
  +--> index
  +--> offset
  +--> byte offset

                       +--------------------------+
index ---------------->| valid_arr[2][LINE_NUM]   |
tag ------------------>| tag_arr[2][LINE_NUM]     |
offset --------------->| data_arr[2][LINE_NUM]    |
                       | dirty_arr[2][LINE_NUM]   |
                       | lru_arr[2][LINE_NUM]     |
                       +------------+-------------+
                                    |
                  +-----------------+-----------------+
                  |                                   |
             compare way0                         compare way1
                  |                                   |
                  +--------------- hit ---------------+
                                    |
                       hit_cpu / rdata_cpu
```

### 9.2 工作原理说明

`CacheBank` 是一个二路组相联、写回式、写分配式的缓存存储体。  
对 CPU 发来的每个访问地址，模块会先把地址拆成 `tag/index/offset`：

- `index` 用于选择当前访问的是哪一组
- `tag` 用于和两路 cache line 的 tag 比较
- `offset` 用于在命中的 cache line 内部选择第几个 64 位 word

随后模块并行检查两路：

- 若某一路 `valid=1` 且 `tag` 相等，则该路命中
- 若两路都不命中，则认为当前访问发生 miss

对读命中：

- 根据命中的 way 和 `offset`，直接从 `data_arr` 中取出对应 64 位数据

对写命中：

- 根据 `wmask` 按字节改写命中路中的对应数据
- 同时把该路 `dirty` 位置 1，表示该行已经和内存不一致

对 miss：

- 输出 `miss_cache`
- 输出待读取行首地址 `addr_cache`
- 根据 LRU 信息输出应被替换的路号 `set_cache`
- 如果 victim line 为脏，则同时输出 `addr_wb` 和 `data_wb`，交给 write-back buffer 暂存

因此，`CacheBank` 本质上只负责“存储与命中判断”，而 miss 之后和内存的具体交互，由外部的 CMU 负责完成。

---

## 10. 思考题 2：展示 hit、miss、write back 的波形/时序，并分析周期

严格提交报告时，最好用 GTKWave 截图。  
这里我先给出**等价的时序表分析**，它已经足够说明原理，也更便于你直接写成报告文字。

### 10.1 情况一：Cache hit

以普通 load hit 为例，可等价描述为：

```text
Cycle N:
  ren_cpu     = 1
  hit_cpu     = 1
  miss_cache  = 0
  cmu_state   = IDLE
  busy_rd     = 0
  wen_rd      = 0

同拍即可从 data_arr 中读出 rdata_cpu
```

结论：

- hit 不触发 CMU
- 不需要 line refill
- 不需要 write back
- 对流水线来说，通常没有额外 stall

所以从 CPU 视角，**hit 的额外代价近似为 0**。

### 10.2 情况二：read miss，且 victim 不是脏行

一种典型时序如下：

```text
Cycle N:
  ren_cpu     = 1
  hit_cpu     = 0
  miss_cache  = 1
  cmu_state   : IDLE -> READ

Cycle N+1 ~ ...:
  ren_mem     = 1
  beat_count  = 0

当第 0 个 beat 返回:
  read_resp_fire = 1
  wen_rd         = 1
  CacheBank 写入第 0 个 64-bit word

后续第 1/2/3 个 beat 重复上述过程

最后一个 beat 返回时:
  finish_rd      = 1
  valid_arr[set][index] 被置 1
  cmu_state      : READ -> IDLE
```

如果下层内存在每个 beat 上都能很快应答，那么 refill 至少也要经历：

1. 发出 miss 请求
2. 四个 64-bit beat 的传输
3. 最后一拍把 line 标记为有效

因此 miss 的代价远大于 hit。

### 10.3 情况三：read miss，且 victim 是脏行

这种情况下时序会分成两段：

```text
第一段：先 refill 新行
  IDLE -> READ
  逐 beat 读入新行
  finish_rd=1

第二段：再写回旧脏行
  READ -> WRITE
  逐 beat 把 write-back buffer 里的旧数据写回内存
  finish_wb=1
  WRITE -> IDLE
```

但因为使用了 write-back buffer 和 read priority，**流水线真正关心的是第一段 refill 什么时候完成**。  
也就是说，只要 miss 的新行已经回到 Cache，CPU 后续访问这行时就可以重新 hit；旧脏行的写回可以在后面继续进行。

这是 write-back buffer 最有价值的地方。

### 10.4 我这次实现里的一个额外路径：store miss 直写

除了实验文档的标准 write-allocate / write-back 路径，我还做过一版实验性优化：

- 普通 load miss：仍然 refill
- 普通 store hit：仍然写 Cache
- 某些 store miss：直接向内存发单次写，不做 line refill

它的理想时序类似：

```text
Cycle N:
  cacheable_store_miss = 1

若写通道空闲:
  store_miss_req_fire = 1

若响应未同拍返回:
  store_miss_pending = 1

响应回来:
  store_miss_resp_fire = 1
  store_miss_pending   = 0
  hit_cpu              = 1   // 从 Core 视角看，这笔 store 完成了
```

它的优点是：

- 对“只写一次、不太会马上重用”的地址，避免整条 line refill 的代价

它的风险是：

- 如果同一行数据已经在 Cache 里，就要非常小心一致性问题
- 如果写响应通道和别的事务共用，就要非常小心响应归属问题

这也是为什么我后面又专门给写响应通道补了 `write_owner_q` 仲裁。

### 10.5 这一题真正该分析的结论

你写思考题 2 时，真正要说清楚的不是“我截了几张图”，而是下面三点：

1. hit 路径不经过 CMU，所以代价最小。
2. miss 路径必须经历整条 line 的 refill，所以代价显著上升。
3. 如果 victim 还是脏的，那么还要多出 write back，但借助 write-back buffer 可以把“旧行写回”尽量从关键路径上移开。

---

## 11. 思考题 3

按你这次的要求，**思考题 3 跳过，不写入本说明的答案部分**。

---

## 12. 当前这份代码最终达到了什么状态

从最终行为上看，这份实现已经达到下面这个状态：

### 12.1 `verilate_sort`

- 排序输出正确
- 会在 `unimp` 处以实验文档允许的方式结束

这个现象在 Lab2 里是正常的，不需要再试图把结尾的那一下 mismatch 完全“消掉”。

### 12.2 `kernel`

当前我最终保留的实现，已经可以看到：

```text
...task_init done!
[P=2] 1
[P=2] 2
...
[P=2] 9
[P=1] 1
```

这说明：

- `task_init` 已经完成
- 调度器已经开始切换线程
- 用户可见输出里已经出现不同 `P=` 的切换结果

这正是实验文档要求观察到的关键现象。

### 12.3 还剩什么边角问题

当前还存在一个比较孤立的 warning：

- `csrr a5, mip` 首次读取时，DUT 和参考模型在 `mip` 的可见性上有时序差异

这更像是 CSR 中 timer pending 位的时序细节，而不是会把整个内核直接带崩的主故障。

---

## 13. 最后总结：这次实验最该真正学会什么

如果把这次 Lab2 压缩成几句话，我觉得最值得记住的是：

### 13.1 Cache 不是独立模块，而是系统时序放大器

它会把原来被慢总线掩盖的问题全部暴露出来。  
所以接 Cache 之后，真正需要重查的是整条流水线。

### 13.2 `valid` 必须和副作用绑定

只把 `valid` 置 0 不够。  
`we_reg/we_mem/we_csr/csr_ret` 这些副作用信号也必须同步归零。

### 13.3 ready-valid 逻辑一定要区分“请求发出”和“响应完成”

同拍响应、跨拍响应、共享响应通道，这些细节会直接决定 Cache 和总线是否稳定。

### 13.4 调试时要找“第一处架构分歧”，不要只盯最后崩溃点

最后的崩溃点通常只是后果。  
真正有价值的是最早那个“从这里开始跑偏了”的时刻。

### 13.5 超时未必是性能问题

死锁、活锁、错误提交、不一致数据，都可能表现成“程序跑不完”。  
先保 correctness，再谈优化，几乎总是对的。

---

## 14. 如果你准备自己重写，建议的检查清单

最后给你一个最实用的版本。

每做完一步，检查一次：

1. `CacheBank` 的 hit/miss、dirty、LRU 是否都符合预期。
2. `Cache.sv` 的 READ/WRITE 状态机是否能正确处理四个 beat。
3. `Icache.sv` 接入后，取指 miss 能否停住并恢复。
4. `Dcache.sv` 里的 MMIO 是否绝不进入 Cache。
5. `Core.sv` 的 `if_stall`、`mem_stall`、`stall`、`flush` 优先级是否自洽。
6. invalid bubble 是否真的不再携带副作用。
7. `make verilate_sort` 是否恢复到“排序成功 + `unimp` 结束”的正确现象。
8. `make kernel 2>/dev/null` 是否至少能看到线程切换。

如果这 8 条都过了，这个实验你基本就不只是“做出来了”，而是真的理解了。
