#!/bin/sh
# Shared execution helpers for native bootstrap tests. The compiler executable
# runs on PSL_NATIVE_COMPILER_HOST_TARGET; generated fixtures use output_target.

bootstrap_test_runner_init() {
  output_target=$1
  native_compiler=${PSL_NATIVE_COMPILER:-$project_root/build/pslcc-native}
  compiler_host_target=${PSL_NATIVE_COMPILER_HOST_TARGET:-x86_64-linux-gnu}
  case $compiler_host_target in
    x86_64-linux-gnu) compiler_host_suffix=; run_compiler_host() { "$@"; } ;;
    x86_64-windows-gnu) compiler_host_suffix=.exe; run_compiler_host() { WINEDEBUG=-all wine "$@"; } ;;
    aarch64-linux-gnu) compiler_host_suffix=; run_compiler_host() { qemu-aarch64 -L "${AARCH64_SYSROOT:-/usr/aarch64-linux-gnu}" "$@"; } ;;
    riscv64-linux-gnu) compiler_host_suffix=; run_compiler_host() { qemu-riscv64 -L "${RISCV64_SYSROOT:-/usr/riscv64-linux-gnu}" "$@"; } ;;
    *) echo "unsupported compiler host target: $compiler_host_target" >&2; return 2 ;;
  esac
  case $output_target in
    x86_64-linux-gnu) target_cc=${CC:-cc}; target_suffix=; run_target() { "$@"; } ;;
    x86_64-windows-gnu) target_cc=${WINDOWS_CC:-x86_64-w64-mingw32-gcc}; target_suffix=.exe; run_target() { WINEDEBUG=-all wine "$@"; } ;;
    aarch64-linux-gnu) target_cc=${AARCH64_CC:-aarch64-linux-gnu-gcc}; target_suffix=; run_target() { qemu-aarch64 -L "${AARCH64_SYSROOT:-/usr/aarch64-linux-gnu}" "$@"; } ;;
    riscv64-linux-gnu) target_cc=${RISCV64_CC:-riscv64-linux-gnu-gcc}; target_suffix=; run_target() { qemu-riscv64 -L "${RISCV64_SYSROOT:-/usr/riscv64-linux-gnu}" "$@"; } ;;
    *) echo "unsupported output target: $output_target" >&2; return 2 ;;
  esac
}
