#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
target=${1:-x86_64-linux-gnu}

case $target in
  x86_64-linux-gnu)
    objcopy_tool=objcopy
    target_compiler=cc
    machine=62
    flags=0
    ;;
  aarch64-linux-gnu)
    objcopy_tool=aarch64-linux-gnu-objcopy
    target_compiler=aarch64-linux-gnu-gcc
    machine=183
    flags=0
    ;;
  riscv64-linux-gnu)
    objcopy_tool=riscv64-linux-gnu-objcopy
    target_compiler=riscv64-linux-gnu-gcc
    machine=243
    flags=4
    ;;
  *) echo "unsupported ELF writer target: $target" >&2; exit 2 ;;
esac

run_target() {
  case $target in
    x86_64-linux-gnu) "$1" ;;
    aarch64-linux-gnu)
      qemu-aarch64 -L "${AARCH64_SYSROOT:-/usr/aarch64-linux-gnu}" "$1" ;;
    riscv64-linux-gnu)
      qemu-riscv64 -L "${RISCV64_SYSROOT:-/usr/riscv64-linux-gnu}" "$1" ;;
  esac
}

"$project_root/pslcc" --target="$target" -c \
  "$project_root/tests/bootstrap_answer.lisp" \
  -o "$work_dir/stage0.o"
cp "$work_dir/stage0.o" "$work_dir/extract.o"
"$objcopy_tool" --dump-section .text="$work_dir/code.bin" \
  "$work_dir/extract.o"

for level in 0 1; do
  "$project_root/pslcc" "-O$level" -c \
    "$project_root/bootstrap/object/elf64.lisp" \
    -o "$work_dir/writer-O$level.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_elf64.c" \
    "$work_dir/writer-O$level.o" -o "$work_dir/writer-O$level"
  "$work_dir/writer-O$level" "$work_dir/code.bin" \
    "$work_dir/native-O$level.o" "$machine" "$flags"
  cmp "$work_dir/stage0.o" "$work_dir/native-O$level.o"
  "$target_compiler" -Wall -Wextra -Werror \
    "$project_root/tests/harness_bootstrap_answer.c" \
    "$work_dir/native-O$level.o" -o "$work_dir/answer-O$level"
  run_target "$work_dir/answer-O$level"
done

"$project_root/pslcc" -O1 -c "$project_root/bootstrap/object/elf64.lisp" \
  -o "$work_dir/repeat.o"
cmp "$work_dir/writer-O1.o" "$work_dir/repeat.o"

echo "PSL native ELF writer passed for $target"
