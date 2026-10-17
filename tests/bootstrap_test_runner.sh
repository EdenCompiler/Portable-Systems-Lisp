#!/bin/sh
# Shared execution helpers for native bootstrap tests. The compiler executable
# runs on PSL_NATIVE_COMPILER_HOST_TARGET; generated fixtures use output_target.

# API receiver tests reuse immutable compiler fixtures only inside a full gate.
# MODE COMPILER LEVEL TARGET PROFILE SOURCE OUTPUT; standalone gates compile fresh.
bootstrap_fixture_compile() {
  python3 "$project_root/tests/bootstrap_fixture_cache.py" "$project_root" "$@"
}

# Link the managed runtime explicitly for hosted compiler API receivers. User
# objects keep their independently selected freestanding/hosted profile.
bootstrap_link_runtime() (
  compiler=$1
  shift
  case $output_target in
    x86_64-linux-gnu|aarch64-linux-gnu|riscv64-linux-gnu) runtime_platform=linux ;;
    x86_64-windows-gnu) runtime_platform=windows ;;
    *) echo "unsupported runtime target: $output_target" >&2; exit 2 ;;
  esac
  for source in value cons string symbol package closure vector values gc startup; do
    runtime_source=$project_root/runtime/$source.c
    found=false
    for argument do
      case $argument in "$runtime_source"|*/$source.c) found=true ;; esac
    done
    if test "$found" = false; then set -- "$@" "$runtime_source"; fi
  done
  platform_found=false
  for argument do
    case $argument in */platform_*.c|*/platform*.o|*/runtime-platform*.o|platform*.o) platform_found=true ;; esac
  done
  if test "$platform_found" = false; then
    runtime_object=${work_dir:-${TMPDIR:-/tmp}}/runtime-platform-$output_target.o
    if test ! -f "$runtime_object"; then
      "$target_cc_binary" -O0 -std=c11 -Wall -Wextra -Werror \
        -c "$project_root/runtime/platform_$runtime_platform.c" -o "$runtime_object"
    fi
    set -- "$@" "$runtime_object"
  fi
  "$compiler" "$@"
)

# C receivers that link a compiler core or driver need its declared hosted
# runtime imports. Keep ordinary user-object link recipes unchanged.
bootstrap_target_cc() {
  needs_runtime=false
  compile_only=false
  for argument do
    case $argument in -c|-E|-S) compile_only=true ;; esac
    case ${argument##*/} in
      native-core*.o|core-*.o|*-core.o|api-native.o|api-stage0.o|native-host*.o|host-*.o|*-host.o)
        needs_runtime=true ;;
    esac
  done
  if test "$needs_runtime" = true && test "$compile_only" = false; then
    bootstrap_link_runtime "$target_cc_binary" "$@"
  else
    "$target_cc_binary" "$@"
  fi
}

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
    x86_64-linux-gnu) target_cc_binary=${CC:-cc}; target_suffix=; run_target() { "$@"; } ;;
    x86_64-windows-gnu) target_cc_binary=${WINDOWS_CC:-x86_64-w64-mingw32-gcc}; target_suffix=.exe; run_target() { WINEDEBUG=-all wine "$@"; } ;;
    aarch64-linux-gnu) target_cc_binary=${AARCH64_CC:-aarch64-linux-gnu-gcc}; target_suffix=; run_target() { qemu-aarch64 -L "${AARCH64_SYSROOT:-/usr/aarch64-linux-gnu}" "$@"; } ;;
    riscv64-linux-gnu) target_cc_binary=${RISCV64_CC:-riscv64-linux-gnu-gcc}; target_suffix=; run_target() { qemu-riscv64 -L "${RISCV64_SYSROOT:-/usr/riscv64-linux-gnu}" "$@"; } ;;
    *) echo "unsupported output target: $output_target" >&2; return 2 ;;
  esac
  target_cc=bootstrap_target_cc
}
