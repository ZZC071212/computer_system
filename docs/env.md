# 环境配置与预备知识

## 实验环境

- **HDL**：Verilog、SystemVerilog
- **IDE**：Vivado
- **开发板**：Nexys A7
- **软件辅助环境**：Ubuntu 22.04+

### 环境基础

对于之前没有做过系统一二的同学，或者想要重新配置环境的同学，你至少需要安装 riscv64 交叉编译工具链，以及自行编译 verilator：

- RISC-V 工具链：

    ```bash
    # 使用 glibc 标准库的工具链（linux-gnu）
    sudo apt install gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu
    # 使用 riscv-newlib 的工具链（unknown-elf）
    sudo apt install gcc-riscv64-unknown-elf
    ```

- 编译 verilator：

    ```bash
    # 安装依赖
    sudo apt install git help2man perl python3 make autoconf g++ flex bison ccache
    sudo apt install libgoogle-perftools-dev numactl perl-doc
    sudo apt install libfl2
    sudo apt install libfl-dev
    sudo apt install zlibc zlib1g zlib1g-dev
    sudo apt install device-tree-compiler
    # 克隆最新 verilator 仓库
    git clone https://github.com/verilator/verilator.git
    # 编译安装
    cd verilator
    autoconf
    ./configure
    make -j `nproc`
    sudo make install
    ```

!!! warning
    有了这两个环境，一般的同学（x86_64 架构）就可以进行实验了，我们在 sys-project 中提供了 x86_64 版本的其他环境依赖，**不需要自行编译环境**。对于例如使用 mac M 芯片等 arm 架构的同学，需要参考下一节中的内容自行编译环境。

### 工具管理

为了方便同学们编译安装各类工具链，比如 spike、verilator 等，我们使用 gitsubmodule 机制管理这些工具链仓库。这些仓库被我们管理在 repo 文件目录下：

```
.
└── repo
    ├── Makefile
    ├── opensbi
    ├── patch
    ├── riscv-isa-cosim
    ├── riscv-openocd
    ├── sys-project
    └── verilator
```

- Makefile：用于编译安装各个工具链的脚本
- patch：该文件夹是其他仓库在编译安装之前需要做的修改补丁，运行 makefile 编译这些仓库的时候会自动加入这些补丁
- opensbi：运行 `make fw_jump` 即可编译 opensbi 得到 fw_jump.bin 用于在 qemu、spike 模拟 kernel 的时候充当 sbi，编译得到的 fw_jump.bin 保存在 sys-project/spike 文件夹中
- riscv-openocd：运行 `make openocd` 即可编译安装 openocd 到 /usr/local/bin 中
- riscv-isa-cosim：运行 `make ip_gen` 得到差分测试需要的 ip 文件夹
    - 部分同学因为是 mac 机器无法使用我们已经编译好的 ip 文件夹，这个时候可以运行 `make ip_gen` 自行编译；运行 `make spike` 编译安装 spike 模拟器
- verilator：运行 `make verilator` 编译安装 verilator 工具
- sys-project：实验依赖的其他代码，我们之后详细介绍

!!! note
    同学们如果想要编译某一个工具链，比如工具 openocd：

    1. 首先运行 `git submodule update --init repo/riscv-openocd`
        - 该命令会将 riscv-openocd 仓库 clone 到 repo/riscv-openocd 文件夹
    2. 然后在 repo 文件夹下运行 `make openocd` 即可编译安装 openocd 工具

    如果想要一次性同步所有的子模块，可以直接运行 `git submodule update --init`。

!!! tip
    一般情况只需要同步 sys-project 即可，其他 submodule 均是用于自行编译工具链环境的（例如给出的 x86_64 的 ip 不能在自己的机器上使用）。

### sys-project 文件结构介绍

sys-project 用于提供我们实现好的硬件代码，并且按照代码的功能进行了分门别类：一方面同学们写的代码不会和我们提供的代码混在一起，方便同学们定位自己需要的代码，以及将注意力集中在自己编写的代码上；另一方面也防止部分同学擅自修改代码，来绕过我们的测试点。

#### 硬件部分

- general：提供给同学们的既用于仿真、也用于综合的代码
- include：提供的一些头文件
- ip：用于差分测试的 spike 静态链接库和头文件，和 sim 文件配合进行差分测试
    - 当前 ip 文件夹提供的静态链接库是 x86 架构的，如果部分同学不是 x86 的机器，请在 repo 文件夹运行 `make ip_gen` 自行编译静态链接库
- sim：仅用于仿真的 v、sv、cpp 代码
- spike：spike 模拟器运行测试 kernel 时充当 sbi 的 fw_jump.bin，也可以在 repo 文件夹运行 `make fw_jump` 自行编译
- syn：仅用于综合的 v、xcd、ucf、sv 代码
- tcl：vivado 用于综合的脚本

#### 软件部分

testcode 文件夹下：

- dummy: 空的 dummy.hex 文件，用于初始化不需要初始化的内存
- rom: 不下板综合时使用，代码功能为从 0 地址跳入 0x80000000 地址，初始化 0-0x1000 的内存
- minisbi: 充当 kernel 运行时的 sbi，初始化 0x80000000-0x80200000 的内存
- kernel: Makefile 编译的时候自动产生，是一个指向同学们自己编写的 kernel 代码的软链接
- bootloader: 下板综合时使用，功能是将 0x10000-0x14000 存储的 minisbi，kernel 的内容载入到 0x80000000 的内存中，初始化 0-0x10000 的内存
- compress_elf: 用于将 minisbi、kernel 编译得到的 elf 压缩为初始化 0x10000-0x14000 的 elf.hex
- testcase: 初始化 0-0x1000 的内存，进行简单的功能测试

编译方式如下，不过多数时候不需要手动执行 Makefile 进行编译：

- 运行 `make sim` 得到 testcode/rom、testcode/minisbi、testcode/kernel 的编译结果
    - rom.hex、dummy.hex、kernel.hex 用于分别初始化三块内存
- 运行 `make board` 得到 testcode/bootloader、testcode/compress_elf、testcode/minisbi、testcode/kernel 的编译结果
    - bootloader.hex、elf.hex、dummy.hex 用于分别初始化三块内存
- 运行 `make -C testcase TESTCASE=xxx`，编译其中指定的测试样例
    - 例如 `TESTCASE=sample`，编译 sample 文件夹的测试样例，得到 sample.hex
    - 如果需要得到综合下板的测试样例，则运行 `make -C testcase board TESTCASE=xxx`，这样执行完毕可以顺利死循环在 pass 指令处

### 软件实验环境配置
如已经在系统II更新过相关工具，可忽略下面部分。
#### 更新OpenSBI、Spike
由于我们的实验更新到了 SBI v2.0 规范，因此需要更新 Spike 与 OpenSBI 固件以支持新的 SBI 接口。

进入 repo 目录，执行以下命令：
```
git submodule update --init opensbi
git submodule update --init riscv-isa-cosim
make fw_jump
make spike
```
构建完成后，可能需要 sudo make spike 以将 Spike 安装到系统路径中。请确保 OpenSBI 在 bootload 时输出的 Runtime SBI Version 为 2.0。

``` linenums="0" hl_lines="1 30"
OpenSBI v1.5
   ____                    _____ ____ _____
  / __ \                  / ____|  _ \_   _|
 | |  | |_ __   ___ _ __ | (___ | |_) || |
 | |  | | '_ \ / _ \ '_ \ \___ \|  _ < | |
 | |__| | |_) |  __/ | | |____) | |_) || |_
  \____/| .__/ \___|_| |_|_____/|____/_____|
        | |
        |_|

Platform Name             : riscv-virtio,qemu
Platform Features         : medeleg
Platform HART Count       : 1
Platform IPI Device       : aclint-mswi
Platform Timer Device     : aclint-mtimer @ 10000000Hz
Platform Console Device   : uart8250
Platform HSM Device       : ---
Platform PMU Device       : ---
Platform Reboot Device    : syscon-reboot
Platform Shutdown Device  : syscon-poweroff
Platform Suspend Device   : ---
Platform CPPC Device      : ---
Firmware Base             : 0x80000000
Firmware Size             : 327 KB
Firmware RW Offset        : 0x40000
Firmware RW Size          : 71 KB
Firmware Heap Offset      : 0x49000
Firmware Heap Size        : 35 KB (total), 2 KB (reserved), 11 KB (used), 21 KB (free)
Firmware Scratch Size     : 4096 B (total), 416 B (used), 3680 B (free)
Runtime SBI Version       : 2.0
```

#### 更新QEMU
由于 Ubuntu 22.04 的 APT 源提供的 QEMU 版本为 6.2，这个版本下的 OpenSBI 也很老，而且在后续页表等实验中也会有严重的潜在 bug，所以请同学们通过 `qemu-system-riscv64 --version` 自查 QEMU 版本，保证其在 8.2.2 及以上（Ubuntu 24.04 的 APT 源提供的 QEMU 版本为 8.2.2）。如果版本过低，请参考 [QEMU Wiki](https://wiki.qemu.org/Hosts/Linux) 自行编译新版 QEMU：

```sh
git clone https://github.com/qemu/qemu.git
cd qemu
sudo apt-get install git libglib2.0-dev libfdt-dev libpixman-1-dev zlib1g-dev ninja-build
./configure --target-list=riscv64-softmmu
make -j$(nproc)

# 若 GitHub 访问受限，可以使用下面的命令下载 QEMU 源码

wget https://download.qemu.org/qemu-8.2.2.tar.xz # 可以切换自己想要的版本
tar xvJf qemu-8.2.2.tar.xz
cd qemu-8.2.2
mkdir build
cd build
../configure --target-list=riscv64-softmmu
make -j$(nproc)
sudo make install
# 如果 qemu-system-riscv64 --version 查询不到，但在 build 目录下 ./qemu-system-riscv64 --version 有显示，可通过下述命令将其安装到系统路径中
sudo ln -s "$PWD"/qemu-system-riscv64 /usr/bin/qemu-system-riscv64
```


## 实验前置要求

由于后续的硬件实验(动态分支预测器、Cache、MMU)都要求我们的CPU能够运行起我们的Kernel，而Kernel必须要求CPU能够支持CSR指令、异常处理机制，因此在进行Lab1前，请务必先完成计算机系统II课程的[综合实验](https://zju-sys.pages.zjusct.io/sys2/sys2-fa25/lab7/) 。


