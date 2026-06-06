# Bonus: ARM 架构下的 RISC-V 交叉编译与运行

!!! info "26.05.27 发布、26.06.17 截止提交"

## 实验环境

本次实验通过华为云的弹性云服务器完成，软件环境为 openEuler 22.03 64bit with ARM。

!!! tip "温馨提示：本次实验大部分时间会花费在环境编译上，建议与其他实验并行进行"

## 配置弹性云服务器（ECS）

华为账号的注册请参见钉钉群内的通知，此处不再赘述。我们再次提醒各位同学尽早注册，学生认证需要人工审核，约会耗费 1~3 天。此外，请确保**完成所有认证**后再加入班级，且确保加入时的信息填写正确，否则老师无法给各位同学的账号发放代金券。

!!! warning "请各位同学在 26.06.01 晚前完成注册和认证，并申请加入班级，6.2 会统一发放代金券"

**加入班级，收到代金券**后，请按如下步骤配置弹性云服务器：

1. 使用华为账号登录网站 <https://console.huaweicloud.com>，进入控制台页面，选择区域为“华北-北京四”。

2. 打开左侧导航栏，在列表中选择“计算” -> “弹性云服务器ECS”，点击 ECS 控制台右上角的“购买弹性云服务器”按钮。

3. 选择“自定义购买”，按照下表配置参数，其他参数均保持默认即可：

    | 参数 | 配置 |
    | ----- | ----- |
    | 计费模式 | 按需计费 |
    | 区域 | 华北-北京四 |
    | 可用区 | 随机分配 |
    | CPU 架构 | 鲲鹏计算 |
    | 规格 | 鲲鹏通用计算增强型 2vCPUs 4GiB kc2.large.2 |
    | 镜像 | 公共镜像，openEuler 22.03 64bit with ARM |
    | 系统盘 | 通用型 SSD 40GB |
    | 网络 - 虚拟私有云 | vpc-default |
    | 安全组 | Sys-WebServer |
    | 弹性公网 IP | 现在购买 |
    | 线路 | 全动态 BGP |
    | 公网带宽 | 按流量计费 |
    | 带宽大小 | 5/10/20 Mbit/s 均可 |
    | 释放行为 | 随实例释放 |
    | 云服务器名称 | sys3sp26-<自己的学号>，例如 sys3sp26-3240123456 |
    | 登录凭证 | 密码 |
    | 密码 | 自行设置密码 |

    - 实例规格也可以选择 kc1.large.4 / kc1.xlarge.2 更多 CPU 和内存的规格，可以加速环境编译过程

4. 点击页面右下角“立刻购买”按钮，若弹出协议同意即可，然后点击“返回云服务器列表”。

5. 在 ECS 控制台列表查看服务器的弹性公网 IP 地址，打开终端输入如下命令：`ssh root@<弹性公网IP地址>`，例如 `ssh root@1.92.115.13`。第一次登录时会出现安全性验证提示，输入 `yes` 即可。然后，按照终端的提示输入上面设置的密码（输入时终端不会显示输入内容）。

6. 界面显示欢迎信息，显示 username 和 hostname 为 `root@sys3sp26-<学号>`，即为成功登录。后续需要再次登录时，输入 `ssh` 命令、输入密码即可。

如果对某步操作有疑问，可以参考钉钉群中给出的 ECS 配置文档，其中配有操作界面的截图。文档中还有关于 ECS 如何关机 / 删除的说明，建议同学们在不进行实验时将 ECS 关机，以节省代金券。完成实验后，请务必删除 ECS 和相关资源，避免代金券耗尽。

!!! warning "请务必不要参考 ECS 配置文档的系统版本要求，该文档给出的系统镜像版本过老，无法完成本次实验。"

## 环境配置 {#env}

### RISC-V 交叉编译工具链

先前的实验中，我们是在 x86\_64 的机器上进行交叉编译，产出 riscv64 的编译产物，并由 qemu-system-riscv64 模拟器上运行。本次 bonus 实验中，我们要配置在 ARM 架构的鲲鹏 CPU 上进行交叉编译。

由于 openEuler 的相关 repo 中没有 riscv64 的交叉编译工具链，所以我们要自行编译：

1. 拉取 riscv-gnu-toolchain 源码：

    ```bash
    dnf install -y git
    git clone --recursive https://github.com/riscv-collab/riscv-gnu-toolchain.git
    # or
    git clone --recursive https://gitee.com/mirrors/riscv-gnu-toolchain.git
    ```

    但通过 git 拉取源码较大，而且可能存在网络问题，所以也可以先在本地下载 ZJUGit 上 14.2.0 版本的工具链源码：<https://git.zju.edu.cn/zju-sys/sys3/riscv-gnu-toolchain-v14.2.0.git>，然后通过 scp 命令上传到服务器然后解压：

    ```bash
    # 在本机上
    scp riscv-gnu-toolchain.tar.gz root@<弹性公网IP地址>:~
    # 在服务器上
    tar xzvf riscv-gnu-toolchain.tar.gz
    ```

2. 安装依赖

    ```bash
    dnf install -y autoconf automake python3 libmpc-devel mpfr-devel gmp-devel gawk bison flex texinfo patchutils gcc gcc-c++ zlib-devel expat-devel ncurses-devel
    ```

3. 进行编译

    ```bash
    mkdir /opt/riscv
    cd riscv-gnu-toolchain
    mkdir build && cd build
    ../configure --prefix=/opt/riscv
    make linux
    ```

    - 此过程会耗费较长时间（超过 1 小时），请耐心等待
    - 在 2c4g 的配置上建议不要使用 `-j` 进行并行编译，服务器内存配置较小，可能会因为内存不足而导致机器卡死
    - `make linux` 为编译 glibc 版本工具链，产物以 riscv64-unknown-linux-gnu- 为前缀；`make` 为编译 newlib 版本工具链，产物以 riscv64-unknown-elf- 为前缀，二者均可，只需注意后续 CROSS\_ 前缀设置即可

4. 检验产物

    ```bash
    /opt/riscv/bin/riscv64-unknown-linux-gnu-gcc --version
    # or
    /opt/riscv/bin/riscv64-unknown-elf-gcc --version
    ```

    - 输出正确版本信息即为成功
    - 可以在 ~/.bashrc 末尾添加 `export PATH=/opt/riscv/bin:$PATH` 来将工具链路径添加到环境变量中，之后重新 source ~/.bashrc 即可直接使用 riscv64-unknown-linux-gnu-gcc 或 riscv64-unknown-elf-gcc 命令

### QEMU 模拟器

由于 repo 中提供的 QEMU 版本是 6.2，这个版本和自带的 OpenSBI 会在页表等实验中有严重潜在 bug，所以为了确保能正确运行起先前写过的 kernel，需要自行编译较新版本的 QEMU（这里以 8.2.2 为例）：

1. 下载源码：

    ```bash
    wget https://download.qemu.org/qemu-8.2.2.tar.xz
    tar xvJf qemu-8.2.2.tar.xz
    cd qemu-8.2.2
    ```

2. 安装依赖

    ```bash
    dnf install -y ninja-build glib2-devel
    ```

3. 进行编译

    ```bash
    mkdir /opt/qemu
    mkdir build && cd build
    ../configure --target-list=riscv64-softmmu --prefix=/opt/qemu
    make
    make install
    ```

4. 检验产物

    ```bash
    /opt/qemu/bin/qemu-system-riscv64 --version
    ```

    - 同样可以将 /opt/qemu/bin 添加到环境变量中，之后直接使用 qemu-system-riscv64 命令

除了 QEMU 外，还需要提供运行时的 OpenSBI，由于 OpenSBI 已经编译至 riscv64 的产物，所以大家可以将先前软件实验中使用的 fw_jump.bin 直接上传到服务器上，然后调整 Makefile 中对 fw_jump.bin 的路径指向即可。

## 实验要求

本次实验分为两个部分，各占总评 2 分，bonus 分数只溢出到平时分 70 分中，不溢出到期末分数。

### Task1：鲲鹏处理器 (ARM) 与 RISC-V 架构对比

需要同学们简要了解鲲鹏处理器及其采用的 ARM 架构，并与先前实验中的处理器和 RISC-V 架构进行对比。只需在实验报告中介绍出你的理解和对比即可，例如 ARM 和 RISC-V 两个指令集架构在设计上的异同。

在 Task2 完成后，你也可以增加你对交叉编译以及 QEMU 的理解，总结先前实验的环境使用和本次 bonus 中在鲲鹏处理器上的环境使用的异同。

### Task2：在鲲鹏处理器上进行 kernel 的编译运行

在根据[环境配置](#env)完成工具链和 QEMU 的安装后，本实验需要同学们在鲲鹏服务器上编译并运行起自己在 [lab5](./lab5.md) 中编写完成的最终 kernel（也可以编译并运行 xpart 中扩展后的 kernel）。

## 实验提交

本次实验无需验收，需要提交实验报告。由于实验不涉及代码编写，实验报告中需附上充分的截图来作为实验完成的证明。报告中至少需要包含以下截图：

- 环境配置部分：
    - 请保留你在环境配置过程中的必要步骤的截图（不要截编译过程中大量输出的冗余截图）
    - 在终端中的截图需要包含 hostname（即 `root@sys3sp26-<学号>`）
    - 工具链和 QEMU 的版本信息
- 编译运行部分：
    - 呈现出你对 Makefile 修改的部分
    - 编译命令和编译开始前几行输出的截图
    - QEMU 运行起 kernel 的效果截图

除此之外，不要忘了在报告中回答 Task1 中的问题。
