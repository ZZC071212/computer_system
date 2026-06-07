# XPart 拓展二：内核输入输出导读

这个拓展让用户态程序能够通过系统调用进行基本输入输出。输出走 SBI Debug Console Write，输入走 SBI Debug Console Read，并通过一个 mini_sbi patch 提供可复现的脚本输入。

## 实现目标

新增能力：

- 用户态 `read()`。
- 用户态 `write()`。
- 内核 `sys_read()`。
- 内核 `sys_write()`。
- `printk()` 支持高地址内核缓冲区输出。
- mini_sbi 的 DBCN read 不再拒绝，而是返回脚本输入。

## 系统调用号和用户态封装

### `src/project/kernel/include/syscalls.h`

新增 syscall 号：

```c
#define __NR_read 63
#define __NR_write 64
#define __NR_getpid 172
#define __NR_clone 220
```

这里沿用常见 RISC-V Linux syscall 编号，方便报告时解释。

### `src/project/kernel/user/include/unistd.h`

声明用户态接口：

```c
#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2

ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
```

### `src/project/kernel/user/src/syscalls.c`

用户态 wrapper 使用 `ecall`：

- `a0/a1/a2` 传 fd、buf、count。
- `a7` 传 syscall number。
- 返回值从 `a0` 取回。

`read()` 和 `write()` 都只是一层用户态封装，真正逻辑在内核。

## 内核 syscall 实现

### `src/project/kernel/arch/riscv/include/ksyscalls.h`

声明内核 syscall：

```c
long sys_read(unsigned fd, char *buf, size_t count);
long sys_write(unsigned fd, const char *buf, size_t count);
long sys_getpid(void);
long sys_clone(struct pt_regs *regs);
```

### `src/project/kernel/arch/riscv/kernel/trap.c`

在用户态 ecall 分发中加入：

- `__NR_read` -> `sys_read(fd, buf, count)`
- `__NR_write` -> `sys_write(fd, buf, count)`
- `__NR_getpid` -> `sys_getpid()`
- `__NR_clone` -> `sys_clone(regs)`

分发后执行：

```c
regs->sepc += 4;
```

这样返回用户态时跳过触发 ecall 的指令。

### `src/project/kernel/arch/riscv/kernel/ksyscalls.c`

这个文件是输入输出拓展的核心。

`kernel_buf_pa()`：

```c
static uint64_t kernel_buf_pa(const void *buf) {
  uint64_t addr = (uint64_t)buf;
  return addr >= VM_START ? addr - PA2VA_OFFSET : addr;
}
```

原因是 mini_sbi 运行在较低层，它接收的是物理地址。内核缓冲区处于高地址 direct map 时，需要先转成物理地址。

`sys_write()`：

- 只接受 `fd = 1` 或 `fd = 2`。
- 把用户传入的 buffer 拷贝到 64 字节内核栈缓冲区。
- 每块通过 DBCN write 输出。
- 返回请求写入的总长度。

`sys_read()`：

- 只接受 `fd = 0`。
- 每次向 DBCN read 请求 1 字节。
- 把 `\r` 规整为 `\n`。
- 读到换行或达到 count 后返回。

这种一字节读取比较慢，但逻辑简单，适合作为 shell 的基础输入能力。

## printk 输出适配

### `src/project/kernel/arch/riscv/kernel/printk.c`

`printk_sbi_write()` 在调用 SBI 前也做高地址到物理地址的转换：

```c
uintptr_t addr = (uintptr_t)buf;
if (addr >= VM_START) {
    addr -= PA2VA_OFFSET;
}
sbi_ecall(0x4442434e, 0, len, addr, 0, 0, 0, 0);
```

这样内核进入高地址空间后，`printk()` 仍能正常输出。

## mini_sbi 输入 patch

### `repo/patch/sys-project/1.patch`

这个 patch 修改子模块文件：

```text
repo/sys-project/testcode/mini_sbi/sbi_trap.c
```

原本 DBCN read 返回 `SBI_ERR_DENIED`，patch 后：

- 新增 `sbi_debug_console_read_byte()`。
- 先从固定脚本读入：
  - `help`
  - `pid`
  - `echo hello from xpart shell`
  - `tlb`
  - `exit`
- 脚本耗尽后回落到 `uart_rx()`。
- DBCN read 返回实际读取字节数。

这个 patch 是测试输入输出和 shell 的必要测试文件。因为 `repo/sys-project` 是子模块，主仓库不能直接提交子模块内部源码，所以用 patch 保存可复现修改。

## 输入输出调用链

```text
user read/write()
  -> ecall
  -> trap_handler()
  -> sys_read/sys_write()
  -> sbi_ecall(DBCN read/write)
  -> mini_sbi sbi_scall_handler()
  -> scripted input or console output
```

## 检验方法

先应用输入 patch：

```bash
git -C repo/sys-project apply ../../repo/patch/sys-project/1.patch
```

然后运行 shell 目标：

```bash
make -C src/project clean
make -C src/project kernel T=SHELL
```

期望看到脚本输入被 shell 读到并回显：

```text
[xpart-shell] read syscall + simple shell ready
commands: help, pid, echo <text>, fork, tlb, exit
$ help
commands: help, pid, echo <text>, fork, tlb, exit
$ pid
pid = ...
$ echo hello from xpart shell
hello from xpart shell
```

也可以使用脚本：

```bash
bash scripts/xpart_verify.sh io
```

## 常见问题

- 如果输出乱码或没有输出，检查 `printk.c` 和 `ksyscalls.c` 是否把高地址 buffer 转成物理地址。
- 如果 shell 一直卡在 `$ `，检查 `repo/patch/sys-project/1.patch` 是否应用到了 `repo/sys-project` 子模块。
- 如果 `read()` 返回 0，检查 mini_sbi DBCN read 的 `a0/a1` 返回值设置。
- 如果用户态 ecall 后反复执行同一条指令，检查 `trap.c` 是否在 syscall 处理后 `regs->sepc += 4`。
