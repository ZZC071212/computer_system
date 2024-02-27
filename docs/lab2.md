# 实验 2：Cache

!!! info "计划 24.03.28 发布、24.04.25 截止验收与提交（四周）"

## 实验目的

- 理解 cache 在 CPU 中的作用
- 了解 cache 与流水线和内存的交互机制
- 理解存储层次（Memory Hierarchy）

## 实验环境

- **HDL**：Verilog、SystemVerilog
- **IDE**：Vivado
- **开发板**：Nexys A7

## 实验原理

### Cache 模块

Cache 作为 CPU 和内存之间的存储结构，能够利用其速度快、容量小的特点，在速度相差较大的两种硬件之间，起到协调两者数据传输速度差异的作用，是 CPU 存储层次中的重要组件。

对于整个 Cache 模块的结构和功能，下图以 D-Cache 为例给出一种参考设计，总体来说 Cache 内部可以再细分至控制模块（橙色）和存储模块（绿色）两个子模块。

- 控制模块负责维护用于管理 Cache 状态的有限状态机，同时对 Cache 同上层 CPU 与下层 Memory 的交互起到调控作用
- 存储模块中则是 Cache 中存储的实际内容，一般为了保证 Cache 功能的正确实现，每个 Block 还需要辅助 Tag（地址高位）、V（有效位）、D（脏数据）等信息进行管理

![image-20230328155418792](lab1.assets/image-20230328155418792.png)

### Cache 存储

我们的 cache 存储是现在 sys-3-project 的 lab2 分支的 general/CacheBank 模块中，定义的数据结构如下：

```Verilog
typedef logic [TAG_LEN-1:0] tag_t;  
// tag 数据类型，address 的最前端部分，为 address[TAG_END:TAG_BEGIN]
typedef logic [INDEX_LEN-1:0] index_t;    
// index 数据类型，address 中充当 cacheline 索引的部分，为 address[INDEX_END:INDEX_BEGIN]，大小等于 LINE_NUM
typedef logic [OFFSET_LEN-1:0] offset_t;
// offset 数据类型，address 中充当 cacheline 内部 quadword 索引的部分，为 address[OFFSET_END:OFFSET_BEGIN]，大小等于 BANK_NUM
typedef logic [BANK_NUM*DATA_WIDTH-1:0] data_t;

typedef struct {
    logic valid;
    // valid 位，当 cacheline 内容有效的时候等于 1，无效时等于 0
    logic dirty;
    // dirty 位，当 cacheline 数据有效且被写入的时候等于 1，未被写等于 0，数据无效则无所谓，配合 write back 策略
    logic lru;
    // lru 位，当 cacheline 这个 way 最近被访问时等于 1，另一个 way 最近被访问时等于 0，配合二路组关联策略
    tag_t tag;
    // tag 位，地址中的 tag 部分
    data_t data;
    // data 位，存储的数据
} CacheLine;
// 一路 cacheline

CacheLine set [1:0][LINE_NUM-1:0];
// 二路组关联策略，有两个 way 的 cache，每个 cache 有 LINE_NUM 个 cacheline
```

之后是这五个数据结构的有限状态机，大家编程之前最好自己仔细阅读，以免调试遇到问题。配合执行的策略是：

1. 二路组关联：一个 index 对应两个 cacheline，可以优先减少因为 index 地址冲突导致的 cache 失配
2. write alloc：写失配时将数据从内存载入 cache，便于之后多次读写该数据的时候可以从内存得到数据
3. write back：写命中时仅修改 cache，当 cacheline 被挤出 cache 时写回内存，避免每次写数据的时候都写内存
4. read 优先：当发生 write alloc 需要将 cacheline 挤出 cache 并且将脏数据写回内存时，首先将数据载入 cache、同时将被挤出 cache 的数据暂存到 cache buffer，然后将被挤出 cache 的数据写回内存，这样 piepline 读 cache 的数据和 CMU 将数据写回内存可以并行，pipeline 无需等待 cache back 的时间，提高执行效率

该模块的各个输入输出作用如下：

```Verilog
module CacheBank #(
    parameter integer ADDR_WIDTH = 64,
    // 地址线路的宽度
    parameter integer DATA_WIDTH = 64,
    // 数据线路的宽度
    parameter integer BANK_NUM = 4,
    // 一个 cacheline 的 word 个数
    parameter integer CAPACITY = 1024
    // cache 可以存储的最大字节数
) (
   // 来自 core 的数据请求
   input clk,
   input rstn,
   input [ADDR_WIDTH-1:0] addr_cpu,
   // 需要读写的地址信号
   input [DATA_WIDTH-1:0] wdata_cpu,
   // 需要写入的数据
   input wen_cpu,
   // 写使能信号
   input [DATA_WIDTH/8-1:0] wmask_cpu,
   // 写使能配套的字节使能信号
   input ren_cpu,
   // 读使能信号
   output [DATA_WIDTH-1:0] rdata_cpu,
   // 读到的数据输出
   output hit_cpu,
   // 是否命中

   // 如果有数据需要写回，这组信号将写回数据送入 write back buffer
   output [ADDR_WIDTH-1:0] addr_wb,
   // 写回数据的地址
   output [BANK_NUM*DATA_WIDTH-1:0] data_wb,
   // 写回数据的地址的内容，直接一个 cacheline
   input busy_wb,
   // write back buffer 回应是否忙
   output need_wb,
   // 向 write back buffer 发送写回暂存请求

   // cache 将自己需要读入的数据信息和要被载入的 cacheline 信息给 CMU
   output [ADDR_WIDTH-1:0] addr_cache,
   // cache 告知 CMU 失配数据的地址
   output miss_cache,
   // cache 告知 CMU 发生了失陪
   output set_cache,
   // cache 告知 CMU 需要写入的 way 的编号
   input busy_rd,
   // CMU 告诉 cache 自己是否忙碌
   
   // CMU 将读到的数据写入 cache 的信号
   input [ADDR_WIDTH-1:0] addr_rd,
   // CMU 告诉 cache 自己从内存读入数据的地址
   input [DATA_WIDTH*2-1:0] data_rd,
   // CMU 告诉 cache 自己从内存读入数据的值
   input wen_rd,
   // CMU 告诉 cache 自己要修改对应 cachline 的值
   input set_rd,
   // CMU 告诉 cache 自己要修改的 cache way 的编号
   input finish_rd
   // CMU 告诉 cache 自己完成了所以的读操作，一个 cacheline 载入完毕
);
```

### Write Back Buffer

如果没有 write back buffer，那么当某次失配发生，载入的数据需要将 cacheline 的脏数据挤占的时候，CMU 的操作一般如下：

1. 将需要被载入的 cacheline 中的脏数据写回 memory，这个过程需要多次写内存操作，每个操作需要多个周期
2. 将需要载入的数据从 memory 读入 cacheline，这个过程需要多次读内存操作，每个操作需要多个周期

步骤一和步骤二都需要 pipeline 进行等待。而如果有了 write back buffer，上述过程如下：

1. 将被挤占的脏数据写入 write back buffer，这个过程可以一个周期完成
2. 将需要载入的数据从 memory 读入 cacheline，这个过程需要多次读内存操作，每个操作需要多个周期
3. 将 write back buffer 中的脏数据写回 memory，这个过程需要多次写内存操作，每个操作需要多个周期

pipeline 仅需要等待步骤一和步骤二，然后就可以继续工作，无需等待步骤三，这个等待的开销比之前少了一半。

write back buffer 定义在 general/WriteBackBuffer 模块中，接口定义如下：

```Verilog
module CacheWriteBuffer #(
    parameter integer ADDR_WIDTH = 64,
    parameter integer DATA_WIDTH = 64,
    parameter integer BANK_NUM = 4
) (
   // 和来自 CacheBank 的数据交互，载入 cachebank 的脏数据
   input clk,
   input rstn,
   input [ADDR_WIDTH-1:0] addr_wb,
   // cachebank 脏数据的地址
   input [BANK_NUM*DATA_WIDTH-1:0] data_wb,
   // cachebank 脏数据的内容
   output busy_wb,
   // 告诉 cachebank 自己是否被占用
   input need_wb,
   // cachebank 表示自己有脏数据需要写入
   input miss_cache,
   // cachebank 表示自己发生了失配，miss_cache=1 的时候 need_wb 才有意义

   // 和 CMU 交互，将数据发送给 CMU 写入内存
   input [$clog2(BANK_NUM)-2:0] bank_index, 
   // CMU 写回数据时向 writebackbuffer 请求要写回第几个 subword
   output [ADDR_WIDTH-1:0] addr_mem,
   // 提供需要写回的地址，地址仅到 index 部分，不包括 offset
   output [DATA_WIDTH*2-1:0] data_mem,
   // 提供需要写回的数据
   input finish_wb
   // CMU 告知 writebackbuffer 写回完毕，write back buffer 再次空闲 
);
```

### Cache 和 memory 的数据传输

cache 和 memory 之间用 mem_ift 接口做数据传输，这里将读写常用的信号包裹起来，方便编程和管理。接口定义在 general/Mem_interface 模块当中，我们顺便介绍一下 interface 的语法。

```Verilog
   // Master 发送给 Slave 的写通道的信号
   typedef struct {
      addr_t waddr;
      // 写入的地址
      ctrl_t wen;
      // 写使能
      data_t wdata;
      // 写入的数据
      mask_t wmask;
      // 字节使能信号
   } Mw_struct;

   // Slave 发送给 Master 的写通道信号
   typedef struct {
      ctrl_t wvalid;
      // 写入数据完成，该信号仅持续一周期
   } Sw_struct;

   // Master 发送给 Slave 的读通道信号
   typedef struct {
      addr_t raddr;
      // 读数据的地址
      ctrl_t ren;
      // 读使能信号
   } Mr_struct;

   // Slave 发送给 Master 的读通道信号
   typedef struct {
      ctrl_t rvalid;
      // 读到的数据有效，仅持续一个周期，这个时候需要立刻接收数据
      data_t rdata;
      // 读到的数据，rvalid=1 时有效
   } Sr_struct;
   // 定义需要的 type 和 struct

   // 接口涉及到的数据线，可以接口是一个大号的 struct，这些是接口的成员变量
   Mw_struct Mw;
   Sw_struct Sw;
   // 读通道的交互数据
   Mr_struct Mr;
   Sr_struct Sr;
   // 写通道的交互数据

   // 定义接口
   modport Master (
        output Mw,
        input Sw,
        output Mr,
        input Sr
    );
    // 面向 Master 设备的接口
    // Mw、Mr 是 Master 到 interface 的输出
    // Sw、Sr 是 interface 到 Master 的输入

    modport Slave(
        input Mw,
        output Sw,
        input Mr,
        output Sr
    );
    // 面向 Slave 设备的接口
    // Mw、Mr 是 interface 到 Slave 的输入
    // Sw、Sr 是 Slave 到 interface 得输出
```

这里我们的 Cache 模块是向 Memory 发送读写信号，所以 Cache 模块是 Master 模块，所以它的 mem_ift 是 Master 接口，因此声明为：

```Verilog
module Cache #(
   parameter integer ADDR_WIDTH = 64,
   parameter integer DATA_WIDTH = 64,
   parameter integer BANK_NUM = 4,
   parameter integer CAPACITY = 1024
) (
   ...
   Mem_ift.Master mem_ift
);
```

如果将 mem_ift 展开其实就是：

```Verilog
module Cache #(
   parameter integer ADDR_WIDTH = 64,
   parameter integer DATA_WIDTH = 64,
   parameter integer BANK_NUM = 4,
   parameter integer CAPACITY = 1024
) (
   ...
   input Mem_ift.Sw_struct mem_ift.Sw,
   input Mem_ift.Sr_struct mem_ift.Sr,
   output Mem_ift.Mw_struct mem_ift.Mw,
   output Mem_ift.Mr_struct mem_ift.Mr
);
```

所以我们的 cache 在和 memory 交互的时候的输入输出就是这里的 mem_ift.Sw、mem_ift.Sr、mem_ift.Mw、mem_ift.Mr 四个结构，然后做对应的输入输出操作。

### Cache 控制逻辑

Cache 的基本结构、映射方式以及写策略等方面的内容在理论课程中已有详细的描述，但在实际实现中，cache 的复杂行为一般由专门的控制模块进行管理，被称作 CMU。CMU 实质上是把 cache 中的状态机部分与 CPU 和 Memory 的交互部分独立出来，作为一个控制单元，控制数据的处理，CMU 基本的架构与交互模式如下图所示：

![image-20230328155433473](lab1.assets/image-20230328155433473.png)

对于 CMU 的控制逻辑，一般可以采用状态机的模式来管理，下图给出了一种可行的状态机类型。该状态机针对 write back 策略进行实现，将 Cache 的行为归纳为 3 个状态。该部分 CMU 并没有专门提供模块封装，大家可以在 Cache 中直接实现，也可以选择封装为 CMU 模块。Cache 总体的模块关系如下：

![cache组成](lab1.assets/cache_co.jpg)

#### 初始化 IDLE 状态

该状态表示有限状态机处于空闲状态不工作。

1. 如果 cacheback 检查未失配，有限状态机保持 IDLE 状态，不发出任何控制信号。
2. 如果 cachebank 检查失配，cachebank 发送给 write back buffer 的脏数据信号载入 write back buffer，cachebank 发送给 CMU 的载入数据信号载入 CMU 的寄存器，进入 READ 状态，rd_busy 变为 1。

![idle->read](lab1.assets/idle2read.jpg)

#### 读事务执行 READ 状态

该状态根据 IDLE->READ 载入 CMU 的地址，将数据写回 addr。这里我们的 cache 的 word 是 64 位，但是 memory 的总线是 128 位（因为 DDR2 的 MIG 支持 128 位读写，可以将 cache-memory 的传输效率提高一倍），所以我们每次可以读入两个 word，而不是一个。然后开始如下操作流程：

1. 将变量 count 初始化为 0
2. 将 cachline 要读的前 2 个 word 的地址写入 mem_ift.Mr，发送读请求
3. 等待 mem_ift.Sr.rvalid=1，得到需要的 2 个 word 数据
    ![read_stage1](lab1.assets/read_stage1.jpg)
4. 根据 CMU 在 IDLE->READ 时候载入的写入 cacheline 的 set、addr，将读到的数据写入 cache
5. count++，再次执行第二步读后续的 2 个 word，直到一个 cacheline 读完，发送 finish_rd
    ![read_stage2](lab1.assets/read_stage2.jpg)
6. 看 write back buffer 是不是 busy，是的话进入 WRITE 状态开始将脏数据写回 memory，不是的话返回 IDLE 状态，完成一次 cache 失配处理，rd_busy 变为 0。
    ![read_stage3](lab1.assets/read_stage3.jpg)

#### 写事务执行 WRITE 状态

该状态将 write back buffer 的数据写回 memory，然后开始如下流程：

1. 将变量 count 初始化为 0
2. 向 write back buffer 请求要写的前 2 个 word 的地址写入 mem_ift.Mw，发送写请求
    ![write_stage1](lab1.assets/write_stage1.jpg)
3. 等待 mem_ift.Sw.wvalid=1，2 个 word 写入完毕
    ![write_stage2](lab1.assets/write_stage2.jpg)
4. count++，再次执行第二步读后续的 2 个 word，直到一个 cacheline 读完，发送 finish_wb
5. 返回 IDLE 状态
    ![write_stage3](lab1.assets/write_stage3.jpg)

### cache 的完整结构

* Core 的 IF、MEM 读写请求发送到 icache 和 dcache，icache、dcache 根据需要将读写请求转发给总线，进而发送给 memory
    ![cache_soc](lab1.assets/cache_soc.jpg)
* 顶层为 Icache、Dcache 负责向上接受来自 core 的 IF、MEM 数据请求，向下向 memory 发送读写请求，作用是将来自 IF 和 MEM 的不同的数据请求格式和 cache 可以处理的数据请求格式做转换
    ![icache_dcache](lab1.assets/icache-dcache.jpg)
* 再内部为 CacheWrap 负责处理 cache 旁路问题，如果启用了 cache_enable 则将数据请求发送给 cache，如果没有开启 cache_enable，则将数据请求直接发送给 memory
    ![cachewrap](lab1.assets/cachewrap.jpg)
* Cache 处理 cache 请求
    ![cache组成2](lab1.assets/cache_co.jpg)
* Axi_lite_MMUer 负责管理 cache_enable，地址 0x5000000 的第一位管理 icache 的 cache_enable，地址 0x5000008 的第一位管理 dcache 的 cache_enable，如果要使用 cache，请先使能这两个 bit
    ![mmuer](lab1.assets/mmuer.jpg)
* Icache 和 Dcache 是完全参数可配置的，可以根据自己的需要配置参数

## 实验要求

在 sys-3-project 中执行 `git checkout lab2` 切换到本次试验的框架，其中已经实现了缓存的包装部分，只需要同学们完成 Cache 模块中的 CMU 部分，测试程序仿真、下板通过即可。

- 关于 cache 读/写策略可以参考 [Cache (computing) - Wikipedia](https://en.wikipedia.org/wiki/Cache_(computing)#Writing_policies)
- 关于 cache 替换策略可以参考 [Cache replacement policies - Wikipedia](https://en.wikipedia.org/wiki/Cache_replacement_policies)

> 同样，只通过仿真测试也是可以拿到大部分分数的，并且如果无法完全完成本次实验，只完成 Cache 模块但没有接入流水线测试或者只上交实验报告也是可以拿到部分分数的。请同学们不要完全放弃本次实验。

### 注意事项

* 自己设计测试样例的时候记得首先开启 MMUer 的 cache_enable
* 如果下板出现时序约束问题，可以考虑将 Cache 的参数变小

## 思考题

1. 请给出测试代码执行完毕之后你使用的 cache 的内容分布
2. 请分析本实验的测试代码中每条访存指令的命中/缺失情况，如果发生缺失，请判断其缓存缺失的类别。
3. 在实验报告分别展示缓存命中、不命中的波形，分析时延差异。

## 实验提交

请在学在浙大上提交以下两份文件：

- 实验报告（pdf）
- project 文件夹压缩包（打包前 `make clean` 清除编译产物）
