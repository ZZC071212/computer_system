# 常见问题及解答

## 实验提交要求

实验提交时需要提交代码压缩包和实验报告。

实验报告要求上传 pdf 文件，其中需要包含以下内容：

- 实验内容及简要原理介绍
- 实验具体过程与代码实现
- 实验结果与分析
- 实验中遇到的问题及解决方法
- 思考题与心得体会
- 对实验指导的建议（可选）

文件命名格式为：sys3-lab*X*-*学号*.pdf（第*X*次实验）

!!! tip
    - 在代码实现部分重点展示设计思路和核心部分代码即可，不需要大段粘贴代码
        - 如要展示代码，需以非纯文本的形式展示（需要使用代码块）
    - 思考题占有一定的分值，需要认真回答
    - 请保持实验报告清晰、简洁

## 关于提问与贡献

实验过程中遇到问题仍然可以通过 issue 提问，或者可以私戳联系助教（通过钉钉、QQ 均可）。

对于实验文档或者实验代码有改进的话，欢迎提交 pull request。

## 关于实验分数比例与迟交政策

Lab 0~5 各实验由 70% 的验收和代码以及 30% 的实验报告组成（暂定）。关于迟交，对于软件和硬件实验进行区分：

- 硬件实验（Lab 0-2）：迟交**每周**扣 10% 分数
- 软件实验（Lab 3-5）：迟交**每天**扣 5% 分数

## Lab3 FAQ

### 我一旦执行 `setup_vm`，就会重新跳转到 `0x80200000`，无法继续执行

这是很可能是因为你在 `setup_vm` 之前没有正确设置 `sp` 寄存器，导致在 `setup_vm` 中使用栈的操作出现了问题。请检查你的代码，确保在调用 `setup_vm` 之前正确设置了 `sp` 寄存器。

此外需要注意，设置的栈地址应当是**物理地址**，类似于 `0x802xxxxx`，而同学们使用**符号拿到的地址**很可能是从 GOT 获得的**虚拟地址**，需要**注意转换**。

### 我卡在了 `relocate` 中，无法继续执行，提示无法访问某块内存

这是因为在 `relocate` 里，我们需要设置 `satp` 寄存器以启用分页机制。但是一旦设置了 `satp` 寄存器，我们就需要通过页表来访问内存，就比如我们需要访问设置完 `satp` 寄存器后的下一条指令。此时我们的 `pc` 仍然是在物理地址空间上的（只有在 `ret` 之后，我们才能通过 `ra` 返回虚拟地址空间），这时候如果等值映射没做好，下一条指令便无法访问到，导致这里无法访问内存的异常。

因此，实现上需要注意等值映射是否正确实现。

### 我尝试对 linear mapping 得到的虚拟地址减去一个 `PA2VA_OFFSET`，却得到一个非常奇怪的地址，而不是我期望的物理地址

需要注意，在 C 语言中，减法操作会根据类型进行计算。例如，如果类型 `A` 是一个占用 16 字节的结构体，那么 `A` 的指针减去 1，会得到一个减去 16 的地址。

因此，推荐在进行减法操作时，先将指针转换为 `uint64` 类型，进行数值计算。

### 在 `setup_vm` 中，我们只做了一级映射，怎么也能正常运行

在 [RISC-V Privileged Spec 4.3.1](https://www.five-embeddev.com/riscv-priv-isa-manual/Priv-v1.12/supervisor.html#sec:translation) 中提及：

!!! quote "4.3.1 Addressing and Memory Protection"
    The permission bits, R, W, and X, indicate whether the page is readable, writable, and executable, respectively. When all three are zero, the PTE is a pointer to the next level of the page table; otherwise, it is a leaf PTE.

因此，是否是 leaf PTE 是由 R, W, X 三个位决定的，并不一定必须要做三级映射。[RISC-V Privileged Spec 4.4.1](https://www.five-embeddev.com/riscv-priv-isa-manual/Priv-v1.12/supervisor.html#addressing-and-memory-protection) 中也提到：

!!! quote "4.4.1 Addressing and Memory Protection"
    Any level of PTE may be a leaf PTE, so in addition to 4 KiB pages, Sv39 supports 2 MiB megapages and 1 GiB gigapages, each of which must be virtually and physically aligned to a boundary equal to its size.