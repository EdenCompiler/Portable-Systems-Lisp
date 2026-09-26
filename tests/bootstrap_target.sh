#!/bin/sh

select_bootstrap_target() {
  case $target in
    x86_64-linux-gnu) compiler=cc; suffix= ;;
    x86_64-windows-gnu) compiler=x86_64-w64-mingw32-gcc; suffix=.exe ;;
    aarch64-linux-gnu) compiler=aarch64-linux-gnu-gcc; suffix= ;;
    riscv64-linux-gnu) compiler=riscv64-linux-gnu-gcc; suffix= ;;
    *) echo "unsupported bootstrap test target: $target" >&2; exit 2 ;;
  esac
}

run_harness() {
  case $target in
    x86_64-linux-gnu) "$@" ;;
    x86_64-windows-gnu) WINEDEBUG=-all wine "$@" ;;
    aarch64-linux-gnu)
      qemu-aarch64 -L "${AARCH64_SYSROOT:-/usr/aarch64-linux-gnu}" "$@" ;;
    riscv64-linux-gnu)
      qemu-riscv64 -L "${RISCV64_SYSROOT:-/usr/riscv64-linux-gnu}" "$@" ;;
  esac
}
