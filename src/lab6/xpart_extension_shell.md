# XPart 拓展三：简易 Shell 导读

这个拓展在用户态实现一个最小 shell，把前面的能力串起来：`read()` 负责输入，`write()/printf()` 负责输出，`getpid()` 展示 syscall，`fork()` 展示进程复制，`tlb` 命令展示 TLB 热页访问。

## 构建入口

### `src/project/kernel/Makefile`

通过 `T` 选择用户程序：

```makefile
T ?= PFH1
export CPPFLAGS := -I$(CURDIR)/include -DUSER_MAIN=$(T)
```

运行 shell 时使用：

```bash
make -C src/project kernel T=SHELL
```

### `src/project/kernel/user/Makefile`

用户程序也接收同一个 `T`：

```makefile
CPPFLAGS += -I$(CURDIR)/include -DUSER_MAIN=$(T)
```

这样内核和用户 app 都能知道当前选择的 `USER_MAIN`。

## Shell 用户程序

### `src/project/kernel/user/src/main.c`

新增目标：

```c
#define SHELL 1150
```

当 `USER_MAIN == SHELL` 时编译 shell 分支。

主要函数：

- `shell_streq()`：判断命令是否完全相等。
- `shell_starts_with()`：处理 `echo ` 前缀。
- `shell_skip_space()`：跳过命令前后的空格。
- `shell_readline()`：调用用户态 `read()` 读取一行，去掉 `\r`/`\n`。
- `shell_tlb_demo()`：反复访问一个 4 KiB 对齐静态页，触发 TLB 热页场景。
- `shell_help()`：输出命令列表。

支持的命令：

| 命令 | 作用 |
| --- | --- |
| `help` | 打印命令列表 |
| `pid` | 调用 `getpid()` 打印当前进程号 |
| `echo <text>` | 回显文本 |
| `fork` | 调用 `fork()`，父进程打印子 PID，子进程保持存活 |
| `tlb` | 运行热页访问 demo 并打印 checksum |
| `exit` | 打印结束信息后停在循环中 |

## Shell 依赖的内核能力

Shell 本身在用户态，但它依赖以下内核模块。

### 输入输出

- `src/project/kernel/user/src/syscalls.c`：用户态 `read/write/getpid/fork` ecall wrapper。
- `src/project/kernel/arch/riscv/kernel/trap.c`：分发 syscall。
- `src/project/kernel/arch/riscv/kernel/ksyscalls.c`：实现 `sys_read/sys_write/sys_getpid/sys_clone`。
- `repo/patch/sys-project/1.patch`：给 mini_sbi 提供可复现的脚本输入。

### fork

- `src/project/kernel/arch/riscv/kernel/proc.c`
  - `do_fork()` 复制 `task_struct`。
  - `copy_mm()` 复制 VMA 链表。
  - `share_present_pages()` 把父进程已映射页设为 COW。
- `src/project/kernel/arch/riscv/kernel/entry.S`
  - `ret_from_fork` 用于子进程第一次被调度时恢复寄存器。
  - `__switch_to` 切换内核栈、`satp`、`sepc`、`sscratch` 等上下文。
- `src/project/kernel/arch/riscv/kernel/trap.c`
  - COW 写 fault 时复制页面并恢复写权限。

### TLB demo

`tlb` 命令调用：

```c
static volatile uint64_t page[512] __attribute__((aligned(0x1000)));
```

它会重复读写同一页。第一次访问可能触发缺页并建立映射，后续访问用于观察 TLB 命中路径。

## 脚本输入

默认测试输入由 `repo/patch/sys-project/1.patch` 写死在 mini_sbi 中：

```text
help
pid
echo hello from xpart shell
tlb
exit
```

没有把 `fork` 放进默认脚本，是为了让自动验收输出保持稳定。`fork` 命令仍然可用；如果要单独展示 fork，可以把 patch 中的脚本改成包含 `fork`，或等脚本耗尽后通过 UART 输入。

## 执行流

```text
make T=SHELL
  -> user/main.c 编译 SHELL 分支
  -> uapp.bin 嵌入内核
  -> 内核启动并创建 1 个 shell 用户任务
  -> shell 打印提示符
  -> read() 从 mini_sbi 脚本取一行
  -> 根据命令调用 getpid/fork/tlb/exit
```

## 检验方法

推荐用脚本自动应用 patch 并检查关键输出：

```bash
bash scripts/xpart_verify.sh shell
```

手动执行：

```bash
git -C repo/sys-project apply ../../repo/patch/sys-project/1.patch
make -C src/project clean
make -C src/project kernel T=SHELL
```

期望输出包含：

```text
[xpart-shell] read syscall + simple shell ready
commands: help, pid, echo <text>, fork, tlb, exit
$ help
commands: help, pid, echo <text>, fork, tlb, exit
$ pid
pid = ...
$ echo hello from xpart shell
hello from xpart shell
$ tlb
tlb demo touched one hot page, checksum = 1161216
$ exit
shell demo done
```

## fork 单独检验

如果要展示 `fork`，可以临时把 `repo/patch/sys-project/1.patch` 中脚本改成：

```text
fork
exit
```

然后重新应用到干净的 `repo/sys-project` 子模块并运行：

```bash
git -C repo/sys-project apply -R ../../repo/patch/sys-project/1.patch
# 修改 patch 后重新 apply
git -C repo/sys-project apply ../../repo/patch/sys-project/1.patch
make -C src/project clean
make -C src/project kernel T=SHELL
```

期望看到：

```text
do_fork: <parent> -> <child>
parent forked child pid = <child>
child shell task alive, pid = <child>
```

## 常见问题

- 如果 shell 没有读取命令，优先检查 mini_sbi read patch。
- 如果 `fork` 后父子返回值不对，检查 `do_fork()` 中父进程和子进程 `a0` 设置。
- 如果 `tlb` 命令 checksum 不稳定，检查用户页映射、TLB 回填和 store page fault 处理。
- 如果 `exit` 后仍有仿真输出，这是因为 shell 进入空循环等待仿真时间耗尽，不是异常。
