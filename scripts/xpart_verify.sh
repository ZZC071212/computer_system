#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-all}
PATCH="$ROOT/repo/patch/sys-project/1.patch"
SYS_PROJECT="$ROOT/repo/sys-project"
LOG_DIR=${LOG_DIR:-/tmp/xpart-verify-logs}
KERNEL_LINK="$SYS_PROJECT/testcode/kernel"
KERNEL_DIR="$ROOT/src/project/kernel"

mkdir -p "$LOG_DIR"

ensure_kernel_link() {
  if [ -L "$KERNEL_LINK" ] || [ -e "$KERNEL_LINK" ]; then
    return
  fi
  ln -s "$KERNEL_DIR" "$KERNEL_LINK"
  echo "[xpart-verify] linked repo/sys-project/testcode/kernel"
}

apply_sys_project_patch() {
  if git -C "$SYS_PROJECT" apply --check "$PATCH" >/dev/null 2>&1; then
    git -C "$SYS_PROJECT" apply "$PATCH"
    echo "[xpart-verify] applied repo/patch/sys-project/1.patch"
  elif git -C "$SYS_PROJECT" apply -R --check "$PATCH" >/dev/null 2>&1; then
    echo "[xpart-verify] sys-project patch already applied"
  else
    echo "[xpart-verify] warning: sys-project patch cannot be applied cleanly" >&2
    echo "[xpart-verify] continue with current repo/sys-project state" >&2
  fi
}

run_kernel() {
  local target=$1
  local log="$LOG_DIR/${target}.log"

  echo "[xpart-verify] running T=$target"
  ensure_kernel_link
  make -C "$ROOT/src/project" clean
  make -C "$ROOT/src/project" kernel "T=$target" | tee "$log"
  echo "[xpart-verify] log: $log"
}

check_base_log() {
  local log="$LOG_DIR/PFH1.log"
  grep -a "task_init done" "$log" >/dev/null
  grep -a "switch to \\[PID" "$log" >/dev/null
  grep -a "\\[U\\].*\\[PID" "$log" >/dev/null
  echo "[xpart-verify] base markers found"
}

check_shell_log() {
  local log="$LOG_DIR/SHELL.log"
  grep -a "\\[xpart-shell\\]" "$log" >/dev/null
  grep -a "commands: help, pid, echo <text>, fork, tlb, exit" "$log" >/dev/null
  grep -a "hello from xpart shell" "$log" >/dev/null
  grep -a "tlb demo touched one hot page, checksum = 1161216" "$log" >/dev/null
  grep -a "shell demo done" "$log" >/dev/null
  echo "[xpart-verify] shell/read/tlb markers found"
}

case "$MODE" in
  base)
    run_kernel PFH1
    check_base_log
    ;;
  io|tlb|shell)
    apply_sys_project_patch
    run_kernel SHELL
    check_shell_log
    ;;
  all)
    run_kernel PFH1
    check_base_log
    apply_sys_project_patch
    run_kernel SHELL
    check_shell_log
    ;;
  *)
    echo "usage: $0 [base|io|tlb|shell|all]" >&2
    exit 2
    ;;
esac
