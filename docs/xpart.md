# Xpart：RV64 MMU 及软硬件贯通综合实验

!!! info "26.05.20 发布、26.06.17 当日验收"

## 前言

在计算机系统Ⅰ、Ⅱ、Ⅲ贯通课程的学习中，我们既学习了处理器架构的设计，设计了基础的 RISC-V 指令，也学习了操作系统的基本原理与设计方法，并在手动编写的 CPU core 上运行编写的简单 kernel。

在这一个实验中，我们将完善自己的 CPU，使其支持虚拟地址转换和缺页异常的发出，运行起 lab5 中编写的 kernel，并在此基础上进行更多更自由的软硬件扩展。

!!! success "关于小组合作"
    本实验允许小组合作完成，小组最多 3 人，也可独立完成。
    
    - 不会因为组队影响分数，单人完成没有加分
    - 小组成员同一分数，不存在分数分配机制，请合理选择队友，合理分工，及时沟通

    按照惯例，组队实验开始后，助教的角色会慢慢淡出。如果你真的需要求助助教，需要先和小组成员一起讨论，debug，然后把你讨论的过程和结果告诉助教，然后再进行接下来的答疑。

!!! info "请在 2026.5.21 23:59 之前在钉钉文档中完成组队"

## 实验目标

恭喜！在经历了三个学期的计算机系统捶打与历练之后，这门课程终究迎来了尾声。我们希望能以 Xpart 为你计算机系统学习画上一个完美的逗号。在 Xpart 中，你将进一步完善你的最小系统。在这个最小系统中，我们期待你至少能够完成以下的目标：

- 在 sys2 最后 project 的硬件基础上，实现 MMU 模块来支持 Sv39 地址翻译功能
    - 即，允许不加入 sys3 的动态分支预测和 cache，如果你在 MMU 基础上兼容了动态分支预测和 cache，则可以获得额外加分
- （可选中间目标）在实现了 MMU 的 CPU 上运行起 lab3 & lab4 中编写的 kernel
- 在 MMU 的基础上实现缺页异常（page fault）的抛出
- 在带有 MMU 和缺页功能的 CPU 上运行起 lab5 中编写的 kernel（最终目标）

完成了以上功能，你就可以获得基础分数 **60 分**。但如果没完成上述功能，即使完成了很多额外功能，本次实验的最高分也会限制为 **80 分**。（具体评分规则见[实验要求及评分标准](#score)）

如果你还想获得剩余的分数，我们提供了一些[拓展方向](#extra)可以供你参考启发。你可以选择实现任意方向与功能，但在你完成的作品中要能够体现出软硬件结合的思想。如果你不确定你的想法是否符合要求，欢迎随时联系助教进行讨论。

## 实验环境

- **HDL**：Verilog、SystemVerilog
- **IDE**：Vivado
- **开发板**：Nexys A7
- **软件辅助环境**：Debian 12 / Ubuntu 24.04

## 必做部分实验原理

### Sv39 分页模式与 MMU

在 [lab3](lab3.md) 中，我们介绍了 RISC-V 的 Sv39 分页模式，并实现了一个创建页表并运行在虚拟地址下的 kernel。关于 Sv39 分页模式我们在这里就不多赘述，大家参考 [lab3](lab3.md) 中的介绍以及 RISC-V 特权级手册即可。

CPU 中 MMU（Memory Management Unit，内存管理单元）是一个不可缺少的部件，其主要有以下三个功能：

- **虚实地址翻译**：在用户访问内存时，将用户访问的虚拟地址翻译为实际的物理地址，以便 CPU 对实际的物理地址进行访问；
- **访问权限控制**：可以对一些虚拟地址进行访问权限控制，以便于对用户程序的访问权限和范围进行管理，如代码段一般设置为只读，如果有用户程序对代码段进行写操作，系统会触发异常。
- **发出缺页异常**：当 Core 违反权限控制对某些内存区域进行访问时，比如访问未经过页表映射的虚拟地址或写入仅可读的地址等情况下，应该抛出缺页异常。

!!! abstract "主要实验目标"
    实现地址转换，使得 CPU 可以运行起 lab3 的 kernel。调试 CPU 中特权级处理的部分，使得 CPU 可以运行起 lab4 最终运行 lab5 中编写的 kernel。

## 必做部分实验步骤

### 基础地址转换功能的实现

大家可以先实现基础的 MMU 地址转换的功能，成功运行起 lab3 的 kernel 之后，再进一步在基础上实现缺页异常。本节将带领你实现基础的地址转换。

![alt text](lab6.assets/image1.png)

上图为我们之前的整个 CPU 的架构图。核内将访存地址发送到总线上，总线转发到对应的设备：比如核内发起对地址 `0x10000000` 的请求，总线就会转发给 uart，实现对串口的访问；发起对 `0x80200000` 的请求，总线就会将请求转发给 Axi DDR。这部分转发由 Axi Interconnect 完成，对核内是无感的。

即，核内可以感知到的只有两次握手：核内首先发出 `request_valid` 的请求，等待总线回复 `request_ready` 即第一次握手成功，即代表与目标设备的连接已建立；核内开启 `reply_ready` 表示准备好接收数据，总线取好数据将 `reply_valid` 置 1 表示数据有效，这样完成了第二次握手。请注意，**握手需要等待的时间是不确定的**，所以如果你是通过生硬的计数来控制等待的拍数，需要修改逻辑为“握手成功转移状态”来应对接下来的实验。

就如同上文所说的，核内对地址翻译其实是无感的。就如同你写的代码一样，不需要关注地址转换一样。你看到用户态程序的是 PC 从 0 开始执行，但是实际上被加载到物理地址的哪里你不知道，也不需要关心。而且我们也说了，总线根据访存的地址在物理上来转发和握手，这个地址必须是物理地址。那么我们就要发出一个疑问，我在核内根据 PC 发出的取 0x0 地址处指令的操作，到内存里面使用真正的物理地址进行访存，到底经过了什么？

所以我们正式引入了 MMU。MMU 所在的位置如下图所示。他 **“劫持”** 了核内发出的访存请求，经过 **一通操作** 后转化为物理地址，然后真正地将这个物理地址发送到总线上。等到内存根据这个物理地址返回了数据，MMU 又把这个数据送回核内，这样在核内，在编程者看来，就是用一个虚拟的地址取回了对应位置上的数据。

![alt text](lab6.assets/image2.png)

在具体说明如何实现之前，我们先来讲解以下为什么对核内是 **“无感”** 的。无感的意思是，你完全不需要更改 Core 里面的逻辑，也不需要更改之前的握手机制。在核内看来，无非就是握手等待的时间变久了一些，而状态转移的条件依然是两次握手成功就可以取得一个数据。

![alt text](lab6.assets/normal_handshake.svg)

具体到波形上来说，上图为正常的握手波形。下图为理想中的加了 MMU 的核内看到的波形。第一次握手等待的时间即使做地址转换的时间。

首先，MMU 先把 mem_ift1 和 mem_ift2 断开，自己做地址转换。因为断开之后，mem_ift1 收不到内存传回的握手信号，所以他就一直保持着 `request_valid` 不变。等到地址转换完成，MMU 拿到物理地址了，再把 mem_ift1 和 mem_ift2 连接起来，将 mem_ift1 即核内的访存地址修改为物理地址。内存传回的握手型号核内可以收到，就会做两次握手的状态转移。

这样，在核内看起来就完成了一次用虚拟地址的访存，但是实际上访存过程被 MMU **“劫持”** 了，握手型号和真正的访存地址都受到 MMU 的控制。

![alt text](lab6.assets/mmu_handshake.svg)

那么我们怎么让 MMU 做到 **“劫持”** 来自核内的访存请求，进而做地址翻译呢？

``` SystemVerilog
module MMU(
    input clk,
    input rst,
    ...
    Mem_ift.Slave core_imem_ift,
    Mem_ift.Slave core_dmem_ift,

    Mem_ift.Master mem_imem_ift,
    Mem_ift.Master mem_dmem_ift
);
```

这是 MMU 模块的部分定义，`core_mem_ift` 就是图中的 mem_ift1，`mem_mem_ift` 就是图中的 mem_ift2。我们通过控制这两个总线的断开与连接，就可以实现处理和更改来自核内的内存请求。

接下来我们想知道，断开核内与内存的总线时，MMU 应该去做什么来拿到物理地址？就是通过访问页表，而页表又存在内存中。所以其实 MMU 在做地址翻译的时候，是通过自己发出内存请求实现的。总的来说，为了实现三级页表翻译，我们需要维护以下的状态：

| 当前状态 | 目标状态 | 转移条件               | 需要做的任务 |
| --------| ---------| ----------------------| ------------|
| IDLE    |   DIRECT  | 核内发出的是物理地址   | 无|
| IDLE    |   PTWALK1 | 核内发出的是虚拟地址   | 无 |
| DIRECT  |   IDLE    | 直接内存访问完成      | `mem_mem_ift` 直连 `core_mem_ift`|
| PTWALK1 |  GETDATA  | 只使用一级页表        | 使用 `mem_mem_ift` 访问第一级页表 |
| PTWALK1 | PTWALK2   | 使用三级页表          | 使用 `mem_mem_ift` 访问第一级页表 |
| PTWALK2 | PTWALK3   | 使用三级页表          | 使用 `mem_mem_ift` 访问第二级页表 |
| PTWALK3 |  GETDATA  | 使用三级页表          | 使用 `mem_mem_ift` 访问第三级页表 |
| GETDATA |  IDLE     | 数据取出完成          | 握手信号直连`core_mem_ift`，访存地址改为物理地址 |

下面对每个阶段进行讲解：

- IDLE 阶段，我们根据 `satp` 寄存器的置位以及特权态的输出 `priv` 来判断当前使用物理地址还是使用虚拟地址。如果 `satp` 寄存器未设置，或者特权在 M 态，那么直接使用物理地址访问；如果 `satp` 寄存器已经设置并且当前特权态不为 M 态，那么需要开始进行地址翻译。

- DIRECT 阶段，说明无需地址转换，直接进行内存访问，简单的将 `core_mem_ift` 与 `mem_mem_ift` 直连就好了。

- PTWALK 表示访问页表。第一级页表的物理地址保存在 `satp` 寄存器中。下一级页表的物理地址保存在上一级页表项中。所以我们以物理地址，使用 `mem_mem_ift` 发出访存请求来获得页表项 PTE (Page Table Entry)。

由于每次 `PTWALK` 也是需要向内存发去请求，所以每次 `PTWALK` 需要拆解为两次握手，下面以访问一级页表 `PTWALK1` 为例。

| 当前状态 | 目标状态 | 转移条件               | 需要做的任务 |
| --------| ---------| ----------------------| ------------|
|PTWALK1_1|PTWALK1_2| `mem_mem_ift.request` 握手成功 |保持 `mem_mem_ift.request_valid`  |
|PTWALK1_2|PTWALK2_1| `mem_mem_ift.reply` 握手成功并且取出的的 PTE 不为 Leaf PTE | 保持 `mem_mem_ift.reply_ready`  |
|PTWALK1_2|GETDATA| `mem_mem_ift.reply` 握手成功并且取出来的 PTE 为 Leaf PTE | 保持 `mem_mem_ift.reply_ready`  |

- GETDATA 阶段，不管是使用一级页表也好，使用三级页表也好，到了这个阶段我们都拿到了 LEAF PTE，即最后一级页表项。也就是地址翻译完成，拿到了一开始 `core_mem_ift` 想访问的虚拟地址的物理地址。所以我们这个时候将 `core_mem_ift` 与 `mem_mem_ift` 的握手信号连接上，将 `mem_mem_ift` 的访存地址更改为从 LEAF PTE 中恢复出来的地址，而不是使用 `core_mem_ift` 发出的虚拟地址。这样在 Core 看来，我们就实现了地址翻译的内存访问。至此，一次内存访问完成。

### 用户态实现及异常抛出

完成了 MMU 实现了虚拟地址转换后，我们也只能运行 lab3 中编写的启用了 Sv39 分页的 kernel 代码。更进一步，大家可以调试并完善自己的 CPU，使得其可以运行起 lab4 中添加了用户模式程序，以及 lab5 中处理了缺页异常并实现了 fork 机制的 kernel。

实验框架的 CSRModule 中实现了 sscratch 寄存器，所以如果实现的 MMU 工作正常，是可以直接运行带有用户模式的 kernel 的。接下来为了支持 demand paging 以及 fork 机制，需要 MMU 可以正常识别并抛出 Page Fault 异常。注意触发 Page Fault 有以下几种情况：

- 读取到的 PTE 的 V 位为 0，或者 R 为 0 且 W 为 1（非法 PTE）；
- 读取到的最后一级 PTE 仍不是叶页表项；
- 叶 PTE 的 R/W/X/U 位与当前特权级、SUM 的 MXR 位判断当前访存权限非法；
    - 本实验中不要求考虑 MXR，只需要判断用户态访问页表是否设置了 U 位即可；

正确实现了 Page Fault 异常的抛出就可以运行起带有 demand paging 和 fork 机制的内核了。

在这一部分中，我们需要新增一个处理异常的状态 `PTWALK_EXC`。在前面的页表翻译过程中，如果某一次页表翻译出现了：

* 某一个 PTE 的 V 位为 0 的，说明还页表还未进行映射。

* 某一次写请求，但是 Leaf PTE 的 W 位为 0 的，说明该页不能写，需要 Copy on Write 机制。

就需要将下一个状态设置为 `PTWALK_EXC`。

在这个状态中，我们需要设置好 `except_mmu` 结构体，这个结构体会被传入到 CsrModule 中，用来产生异常，引导控制流到异常处理入口。在这个结构体中有四个成员：

* `except`: 用来表示是否产生异常，如果产生异常就把该位置 1.

* `epc`: 用来记录产生异常的那条 PC。如果是取指访存发生了异常，则应该置为 IF 阶段的 PC；如果是 MEM 阶段访存发生了异常，则应该置为 MEM 阶段的 PC。

* `ecause`: 记录发生异常的原因，请参照手册给出具体数值。我们需要处理的异常有 Instruction Page Fault，Load Page Fault，Store/AMO Page Fault。请根据不同的情况给出这三个数值。

* `etval`: 记录发生访存异常的访存地址，这个地址是核内发出访存请求的虚拟地址。

### 环境准备及框架代码导读

本次试验需要大家将 repo/sys-project 切换到 sys3-xpart 这个 tag 的版本上：

```bash
cd repo/sys-project
git fetch --tags
git checkout sys3-xpart
```

此外你还需要更新你的 sys3-sp26 仓库（来获取 src/xpart 下的内容）：

```bash
git pull
```

我们已经将 MMU 在 repo/sys-project/general/Axi_Core.sv 中进行了实例化，并且与 Core 进行了连线。你需要在 Core.sv 中添加以下输入输出。

```verilog title="src/project/submit/Core.sv" linenums="0" hl_lines="5 9-12"
module Core (
    input clk,
    input rst,
    input time_int,
    input CsrPack::ExceptPack except_mmu,

    Mem_ift.Master imem_ift,
    Mem_ift.Master dmem_ift,
    output CorePack::data_t satp,
    output logic [1:0] output_priv,
    output CorePack::data_t pc_if,
    output CorePack::data_t pc_mem,
    output logic cosim_valid,
    output CorePack::CoreInfo cosim_core_info,
    output CsrPack::CSRPack cosim_csr_info,
    output logic cosim_interrupt,
    output logic cosim_switch_mode,
    output CorePack::data_t cosim_cause
);
```

为了支持后续的缺页异常处理，请将你 submit 代码中的 CsrModule.sv 更新为 src/xpart/CsrModule.sv，添加了以下输入：

```verilog title="src/xpart/CsrModule.sv" linenums="0" hl_lines="15 20"
module CSRModule(
    input clk,
    input rst,
    input csr_we_wb,
    input CsrPack::csr_reg_ind_t csr_addr_wb,
    input CorePack::data_t csr_val_wb,
    input CsrPack::csr_reg_ind_t csr_addr_id,
    output CorePack::data_t csr_val_id,

    input CorePack::data_t pc_wb,
    input valid_wb,
    input time_int,
    input [1:0] csr_ret,
    input CsrPack::ExceptPack except_commit,
    input CsrPack::ExceptPack except_mmu,

    output [1:0] priv,
    output switch_mode,
    output CorePack::data_t pc_csr,
    output CorePack::data_t satp,

    output cosim_interrupt,
    output CorePack::data_t cosim_cause,
    output CsrPack::CSRPack cosim_csr_info
);
```

请你将 src/xpart/MMU.sv 完成后放入 src/submit 中，MMU.sv 的接口如下：

```verilog title="src/xpart/MMU.sv" linenums="0"
module MMU(
    input clk,
    input rst,
    input CorePack::data_t satp,        // satp寄存器的值
    input [1:0] priv,                   // 当前特权态
    input switch_mode,                  // 核内发生了特权态的切换
    input CorePack::data_t pc_if,       // IF 阶段的 PC，在发生 Instruction Page Fault 时作为 EPC
    input CorePack::data_t pc_mem,      // MEM 阶段的 PC，在发生 Load/Store Page Fault 时作为 EPC

    output CsrPack::ExceptPack except_mmu,  // 传出异常信息

    Mem_ift.Slave core_imem_ift,        // Core 侧的总线
    Mem_ift.Slave core_dmem_ift,

    Mem_ift.Master mem_imem_ift,        // Axi 侧的总线
    Mem_ift.Master mem_dmem_ift
);

    //TODO: Finish your MMU

endmodule
```

### 你可能遇到的问题

#### 初始化时间过长

在 `mm_init` 这一步十分耗时，有以下原因：

* 在 kernel/arch/riscv/include/private_kdefs.h 中定义了 `PHY_SIZE` 的大小，由于硬件资源有限并且初始化时间过长，需要把这个改小，在以下这个数量级是一个比较合适的数字：

    ```c
    #define PHY_SIZE 0x400000
    ```

* mm.c 中初始化相关的 `memset` 函数可以去掉，在跑硬件的时候默认已经初始化为 0。

* 如果做了以上两步还是很慢，原因是从 sys3 开始，软件实验内存初始化采用了 `buddy system`，在初始化的过程中比较耗时间，所以我们不得不开一次历史的倒车，你可以将 mm.c 替换为 sys2 中软件实验用到的 mm.c。至此，初始化慢的问题应该可以得到解决。

    请注意，在 `mm_init` 中需要将结束地址设置为虚拟地址的：

    ```c
    uint8_t *e = (void *)(PHY_END + PA2VA_OFFSET);
    ```

## 拓展方向 {#extra}

本部分是可选的扩展方向介绍，每个选项的分支在实验指导的最后有详细评分标准描述。你可以选择自己想要实现的功能进行实现。

### 微架构硬件加速

#### TLB 地址转换缓冲器

在实现了上面的 MMU 的基础上，由于每次取指、访存都会进行很多次对于页表的读取操作，会消耗非常多的周期，导致系统运行效率非常低。我们可以采用 TLB，以及加入 Cache 等操作来提升地址翻译以及访存效率。

TLB（Translation Lookaside Buffer，地址转换后援缓冲器）也称为快表。简单地说，TLB 就是页表的 Cache，其中存储了当前最可能被访问到的页表项，其内容是部分页表项的一个副本。只有在 TLB 无法完成地址翻译任务时，才会到内存中查询页表，这样就减少了页表查询导致的处理器性能下降。

!!! note "关于 TLB 刷新"
    我们知道不同的进程之间看到的虚拟地址范围是一样的，所以多个进程下，不同进程的相同的虚拟地址可以映射不同的物理地址。这就会造成歧义问题。例如，进程 A 将地址 0x2000 映射物理地址 0x4000。进程 B 将地址 0x2000 映射物理地址 0x5000。当进程 A 执行的时候将 0x2000 对应 0x4000 的映射关系缓存到 TLB 中。当切换 B 进程的时候，B 进程访问 0x2000 的数据，会由于命中 TLB 从物理地址 0x4000 取数据。这就造成了歧义。执行 sfence.vma 指令可以刷新 TLB，以支持在进程切换时将整个 TLB 无效化。切换后的进程都不会命中 TLB，但是会导致性能损失。

!!! abstract "主要实验目标"
    本次实验中大家可以仿照 Cache 实现一个直接映射/组相连的 TLB，并实现在 TLB miss 或进程切换时运行 sfence.vma 的 TLB 刷新。有兴趣的同学还可以研究 sfence.vma 的参数，通过 ASID 等方式来减少 TLB 的刷新。

    更进一步地提升效率，大家还可以将 [lab2](lab2.md) 中实现的 Cache 同时接入到 CPU 中。并通过 CPI 等指标进一步衡量 CPU 的优化程度。

#### Return Stack Buffer (RSB)

​​Return Stack Buffer（RSB）​​是处理器中用于优化​​函数调用返回地址预测​​的硬件机制。当执行 CALL 类指令时，CPU 通常将返回地址（下一条指令地址）压入栈，而 RET 类指令需从栈中弹出该地址以实现跳转。

RSB 通过追踪最近的 CALL 指令，建立独立的堆栈结构缓存返回地址，在遇到 RET 时直接预测目标地址并预载流水线，从而避免访问物理内存栈的开销，减少分支预测错误的停顿。

尝试在带 Cache 的 CPU 实现这个结构，并自己编写测试样例，计算带来的性能提升。

### MMIO 与外设

我们的 CPU 实现了完整的 AXI 总线，你可以非常方便的挂载新设备到总线上，并通过 MMIO 访问。在 sys2 的 lab3 中我们已经实现了 AXI 的卷积加速器，在这一个部分，你可以对 MMIO 外设进行拓展。你可以在 repo/sys-project/sim/dpi.cc 的 `cfg.mmio_layout` 中新增自己的 MMIO 空间。 可选的建议有：

#### 通用计算加速

比如多周期的乘法器 / 除法器，以 AXI 的协议挂载在总线上，实现软乘除法的加速。可以参考卷积加速器的使用方式，为乘除法器指定一个地址范围来放入操作数，指定一个地址范围来取出结果。并计算对比软乘除法的加速比。

!!! tip "让你的软件能够使用加速器"

    软乘除法的实现位于 lib/div.S 与 lib/muldi3.S 中。对于未开启 M 扩展的 CPU，GCC 在编译时会自动将乘除运算替换为软乘除法的实现。如果你实现了乘除法器，你可以进一步修改 lib/div.S 与 lib/muldi3.S 中的乘除法实现，将其替换为对 MMIO 乘除法器的调用。这同样是软件与硬件结合的好例子。

#### 专用硬件加速

比如矩阵乘法器。在当前的 AI 加速器中，有很大一部分加速模块就是专注于对矩阵乘法进行加速。与卷积加速器类似，你可以指定一个地址空间来写入两个矩阵。当矩阵元素放入后，该加速器就可以开始进行矩阵乘法操作。注意，矩阵乘法有很多步骤是没有前后依赖关系的，是可以并行操作的，这可以大大加快运算速度。

计算过程如下。结果矩阵的9个元素可以同时计算出来，这就是并行加速带来的速度提升。更甚，你可以对每一个元素的三个乘法算式再进行并行计算：你只要实例化出 27 个乘法器，你就可以在完成一次乘法和两次加法的时间内计算出这个矩阵乘法运算。你再与你的普通矩阵乘法运算对比，将会是巨大的提升。

\[ \begin{aligned}
& \begin{bmatrix}
1 & 2 & 3 \\
4 & 5 & 6 \\
7 & 8 & 9
\end{bmatrix}
\times
\begin{bmatrix}
11 & 22 & 33 \\
44 & 55 & 66 \\
77 & 88 & 99
\end{bmatrix} = \\
& \begin{bmatrix}
1\times 11 + 2\times 44 + 3\times 77 & 1\times 22 + 2\times 55 + 3\times 88 & 1\times 33 + 2\times 66 + 3\times 99 \\
4\times 11 + 5\times 44 + 6\times 77 & 4\times 22 + 5\times 55 + 6\times 88 & 4\times 33 + 5\times 66 + 6\times 99 \\
7\times 11 + 8\times 44 + 9\times 77 & 7\times 22 + 8\times 55 + 9\times 88 & 7\times 33 + 8\times 66 + 9\times 99
\end{bmatrix}
\end{aligned} \]

你甚至可以使用这个写出一个前向传播的神经网络 demo。

#### DMA (Direct Memory Access)

内存和硬件加速器都是外设，但是在他们之间传递数据还是需要 CPU 的参与。比如将一个矩阵的元素载入到矩阵乘法加速器中。在课程上我们学习了 DMA，DMA也是一种外设，这是一种不需要 CPU 完全介入的内存访问方式，他允许外设之间直接进行内存的相互访问。有没有一种可能，矩阵加速器在收到CPU的指示之后，直接向某个内存地址发出请求，得到矩阵元素。然后直接计算。CPU 需要做的就只有发出指定两个矩阵的首地址即可。

所以 DMA 接受四个 MMIO 写入，即源地址，目标地址，拷贝长度和任务开始。然后提供一个 MMIO 读出，即任务完成。他就根据这几个信号直接与总线进行交互，不需要通过 CPU。需要注意的是，如果你想尝试完成的是内存到内存的 DMA，由于框架无法同步 DMA 对内存的修改， 可以修改框架使其不报错，尝试读出来验证即可。如果你是内存到外设的DMA则无需修改框架。

可以尝试完成这个机制。

### 指令集扩展

在你之前实现的 CPU 上只能实现 RV64I_Zicsr 指令集。但是 RISC-V 还有特别多的指令集拓展，比如 M 的乘除法，F 的浮点运算，A 的原子指令，还有其他的如 V 向量拓展，密码学拓展等等一系列拓展，你可以尝试让你的 CPU 拓展出更多的指令集，做更有意思的事情。

RISC-V 标准定义的部分标准扩展如下：

- Zicsr 扩展：支持 CSR 寄存器和指令
- Zifencei 扩展：支持指令和数据内存栅栏指令
- M 扩展：支持整数乘除法指令
- A 扩展：支持原子内存操作指令
- F 扩展：支持单精度浮点运算指令
- D 扩展：在 F 扩展的基础上，支持双精度浮点运算指令
- Q 扩展：在 D 扩展的基础上，支持四精度浮点运算指令
- C 扩展：支持压缩指令集，即部分指令的编码被压缩至 16 位
- Zam 扩展：在 A 扩展的基础上，支持非对齐原子内存操作指令
- Ztso 扩展：实现强一致性内存模型（Total Store Ordering）

RISC-V 标准又规定，基础 ISA（RV32I / RV64I）和部分扩展（MAFD，Zicsr，Zifencei）综合起来称为 G 扩展，即 IMAFD_Zicsr_Zifencei。可以根据自己的需求和兴趣，选择实现不同的扩展，以丰富自己的 CPU 功能。关于对应扩展的详细信息，可以参考 RISC-V Unprivileged Spec。

进行仿真的时候，你可能需要将 repo/sys-project/sim/dpi.cc 中的 `cfg.isa` 加上相应的扩展名。

#### 浮点运算协同仿真指南

当执行一条浮点运算指令时，你需要为浮点指令解码出浮点寄存器写使能信号，并关闭普通寄存器的写使能信号。假设 WB 阶段该使能信号为 `memwb_frd_we`，那么你需要在 Core.sv 文件的最后，将该信号引出给仿真测试框架：

```verilog
assign cosim_core_info.frd_we     = {63'b0, memwb_out.memwb_frd_we};
```

其余的写地址，写数据还是使用原来的仿真测试信号。

关于我们针对框架做了什么修改使之能够实现浮点寄存器的差分测试，可以查看该 commit: https://git.zju.edu.cn/zju-sys/sys1/sys-project/-/commit/77f2bfeff45d533831b860ecdb0eea06938b7eae

### 支持更多 syscall

在 [lab5](lab5.md) 中，我们完成的 kernel 已经可以支持 getpid、write、fork (clone) 三种 syscall。Linux 中有非常多的 syscall，部分与文件系统相关（如 open、read、write、close），部分与进程管理相关（如 execve、wait、kill），部分与内存管理相关（如 mmap、mprotect），部分与网络相关（如 socket、bind、listen、accept）。你可以尝试实现更多的 syscall，以丰富你的 kernel 功能。

#### execve

execve syscall 在 Linux 中用于执行新的程序。它会加载指定的可执行文件，用新的进程替换当前进程，并传递参数和环境变量。

要实现简易的 execve 功能，你可以修改内核，嵌入多个 uapp 文件。当然，可以进一步结合 [ELF 文件解析](#elf)、[文件系统](#_11)等功能，支持从文件系统中加载可执行文件。

#### 信号

信号是 Unix/Linux 系统中用于进程间通信的一种机制。它允许一个进程向另一个进程发送异步通知，通常用于处理异常情况或实现进程间的协作。

在 Linux 中，信号有很多种类型，例如 SIGINT、SIGTERM、SIGKILL 等。进程可以通过 kill syscall 向其他进程发送信号，或通过 signal syscall 注册信号处理函数。你可以在 kernel 中实现信号处理机制，支持基本的信号发送和接收功能。例如，当按下 Ctrl+C 时，向当前进程发送 SIGINT 信号，并在进程中注册一个信号处理函数来处理该信号（默认行为是终止该进程）。

进一步地，我们在 [lab5](lab5.md) 中实现 fork syscall 时提到，在 RISC-V Linux 中，fork syscall 实际上是通过 clone syscall 来实现的，而我们仅实现了最基础的进程复制功能。若完成了信号处理机制，你可以尝试进一步完善 clone syscall 的功能，支持更多的参数和选项。

#### Shell

Shell 是一个命令行界面，允许用户与操作系统进行交互。你可以实现一个简易的 shell，支持基本的命令解析和执行功能。例如，支持执行内置命令（如 cd、exit）和外部命令（如 ls、cat）。可以使用 fork 和 execve 来实现命令的执行，或进一步通过重定向和管道实现命令之间的通信及文件操作。

!!! abstract "read syscall"

    键盘输入由 SBI 提供接口 `sbi_debug_console_read`，用法与 `sbi_debug_console_write` 类似。你可以借助 `sbi_debug_console_read` 实现从 stdin 的读取操作。

### 完善你的 kernel

#### 内存管理

在 Sys2 Lab 6 中，我们在软件层面引入了（面向 S-mode 的）内存管理，支持以 4 KiB 为单位分配内存。在 [lab4](lab4.md) 中我们引入用户模式，支持以 uapp 的形式运行用户程序。但我们的 uapp 的可用功能仍然受限，例如缺少一个正常的程序中最基本的输入功能，以及没有动态内存分配。我们希望你能在 Xpart 中实现一个更完整的 kernel，支持更多的功能。

以内存管理为例，进程在初始化时，内核会为其分配一块连续的内存空间，作为进程的堆（heap）。进程通过调用内存分配函数（如 malloc）获取一块内存空间，并在使用完毕后通过调用释放函数（如 free）将其归还。需要注意，malloc/free 是纯粹的用户态（libc）函数，其可能调用更底层的 syscall（如 brk、mmap）来实现内存空间的动态扩张与收缩。

!!! note "关于 malloc/free"

    你可以简化实现，例如在固定大小的空间上使用链表来管理内存块的分配与释放，也可以实现如 Slab 等更复杂的内存管理算法。通过 syscall 来辅助 malloc/free 的实现是加分项。

- [Linux 内存管理](https://www.kernel.org/doc/html/latest/mm/index.html)
- [musl libc: src/malloc/mallocng/malloc.c](https://elixir.bootlin.com/musl/v1.2.5/source/src/malloc/mallocng/malloc.c)

另外，你可以从任意角度继续完善你的 kernel，例如更多库函数的实现与更多的 syscall 的支持。

#### 多 hart 调度

在 RISC-V 中，hart（hardware thread，硬件线程）可以被认为是 CPU 的一个逻辑核心。每个 hart 都有自己的 PC、寄存器堆和 CSR 寄存器。有多个 hart 显然的优势是处理器能够并行处理多个任务，提高系统的吞吐量和响应速度。实际上，你可能已经在 Sys2 Bonus 实验中就已经与多 hart 进行了交互：当时的 snprintf 测试中，通过 8 个 hart 来测试你的实现的线程安全性。要开启多 hart 支持，只需在 QEMU 中添加 -smp 参数即可，例如 `-smp 8` 表示开启 8 个 hart。

然而只在 QEMU 层面开启多 hart 支持并不能让你在 kernel 中开箱即用地使用多 hart；hart 的状态管理由 OpenSBI 的 HSM（hart state management）扩展负责，其提供了对 hart 的启用、暂停、恢复等操作的支持。要让你的 kernel 支持多 hart 调度，你需要阅读 SBI v2.0 规范来了解如何与 HSM 进行交互。

进一步地，你可以尝试在 kernel 中实现多 hart 的调度与管理。可以完善 scheduler 逻辑，支持将不同的进程分配到不同的 hart 上同时运行。

你可以阅读 snprintf 测试的源代码以对 HSM 扩展有一个更直观的了解。

### 文件系统

文件系统负责管理存储设备上的数据，提供文件的创建、删除、读写等操作。对于最简单的情况，我们只需在内核中开辟一块空间，支持以文件名为索引的 ORW（Open Read Write）操作，即使以这种方式实现的文件系统会在 kernel 关闭时丢失数据，但也足够体现文件系统的基本原理与思想。

#### VirtIO, VFS & FAT32

对于更复杂的情况，可以实现 VFS（Virtual File System）和 FAT32 文件系统。VFS 是 Linux 内核中实现的一个虚拟文件系统接口，允许不同的文件系统在同一内核中共存。FAT32 是一种常见的文件系统格式，广泛应用于 USB 驱动器和 SD 卡等存储设备。

另外，同学们可以尝试向 QEMU 添加启动参数，以便在 QEMU 中挂载一个可持久化的文件镜像。QEMU 使用 VirtIO 作为虚拟化的 I/O 设备，只需在 kernel 中添加 VirtIO 驱动程序即可实现对 QEMU 中的 VirtIO 设备的访问，进而实现 kernel 的可持久化存储。

- [Linux VFS](https://www.kernel.org/doc/html/latest/filesystems/vfs.html)
- [cccriscv/mini-riscv-os](https://github.com/cccriscv/mini-riscv-os)

#### 实现 ELF 解析

目前我们的 uapp 是以被 strip 为纯二进制的方式嵌入到 kernel 中的，这会导致一些元数据丢失，例如符号表、调试信息、段信息等。我们目前的实现中也处处体现出对此种处理方式的妥协，例如 uapp 的数据部分以 RWX 权限加载到内存中，导致容易出错以及安全隐患。另外，由于 .bss 段不在 ELF 文件中占用空间，导致我们目前需要在 uapp.lds 中进行额外的处理。

我们可以尝试实现 ELF 文件的解析与加载。解析 ELF 文件的头部信息，获取各个段的起始地址和大小等信息，并将其加载到内存中。这样就可以在 kernel 中直接使用 ELF 文件的格式，同时解决了 uapp 的数据部分以 RWX 权限加载到内存中的问题。

- [ELF 文件格式](https://refspecs.linuxbase.org/elf/gabi4+/ch4.eheader.html)

## 实验要求及评分标准 {#score}

### 必做部分

实现 MMU 及 page fault 抛出，运行起 lab5 中的 kernel。

不完成必做部分，则本次实验总评最高限制在 80 分。

### 可选拓展部分

**硬件部分：**

| 实验成果 | 分数 |
|---|---|
| 在 MMU 基础上添加 Cache 模块 | 40 分 |
| 实现 TLB 模块 / RSB 模块 | 各 40 分 |
| 实现外设，如乘法加速器、矩阵乘法加速器、DMA 等 | 分别为 20 分、40 分、40 分 |
| 实现 M 拓展，F 拓展，A 拓展等 | 各 30 分 |

**软件部分：**（只需软件单独仿真即可，不需要搭配硬件实现）

| 实验成果 | 分数 |
|---|---|
| 实现内核的输入输出 | 20 分 |
| 支持 VirtIO 与任意文件的 open、read、write | 20 分 |
| 实现 VFS 与 FAT32 文件系统 | 20 分 |
| 实现 ELF 文件的解析与加载 | 20 分 |
| 实现 shell | 10 \~ 40 分，视完成度而定 |
| 支持多 hart 运行与进程调度 | 40 分 |

另外，我们也鼓励其他有趣的想法，如有其他没列出的扩展方向可以提前与助教沟通。

### 评分方式

类似以往实验的验收分数和报告分数，本次实验的打分方式为：

- 实验基础分值（报告分数）：根据上述分值直接加算得到的基础分值（可能会因为实现不完全而略有扣分）；
    - 如果基础分值超过 100 分，则超过 100 分的部分会以**非等值**的方式计入基础分
- 分值权重（验收分数）：最后一堂实验课当天验收时会进行提问，根据小组同学对各自负责部分的掌握情况来进行打分，分值在 60 \~ 100 分不等。

最终本次实验的总评分数为：基础分值 \* 分值权重 / 100。

!!! note "关于分值权重"

    请同学们放心，只要你独立完成或者和组员一起实现了某一功能，能够解释清实现的方式并回答出相关问题，那么你完全可以拿到 100 分的权重。

    但对于使用 AI 完成实验但自己又并未完全深入理解每一处细节的同学，我们肯定会使用这一部分的权重来进行惩罚。

!!! tip "提醒：小组每位同学分数相同，请自行安排分工，达成组内一致"

### 实验提交验收

本次实验也需要大家在学在浙大上进行提交，请在学在浙大的 `report` 和验收入口分别提交以下文件（组长提交一份即可）：

- 实验报告 (.pdf)
    - 需要在报告中列出小组成员
    - 开头请明确分点写清楚你们小组完成的功能，以及预期得到的基础分值
    - 正文中请简要描述各功能的实现方式、实现效果、遇到的困难以及解决方案等
- 代码压缩包 (.zip), **提交前请清除所有构建产物。**

本次实验将在最后一节课上由各实验班的老师和助教进行统一的验收，请各位同学务必不要缺勤，并且请提前准备好要呈现的内容，节省验收时间。

最后请务必尽快组队并尽快确定分工开始实验，祝大家好运！
