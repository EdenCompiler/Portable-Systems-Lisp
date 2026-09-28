#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
target=${1:-x86_64-linux-gnu}

case $target in
  x86_64-linux-gnu)
    format=elf
    machine=62
    flags=0
    target_cc=cc
    nm_tool=nm
    inspect_tool=readelf
    runner=direct ;;
  aarch64-linux-gnu)
    format=elf
    machine=183
    flags=0
    target_cc=aarch64-linux-gnu-gcc
    nm_tool=aarch64-linux-gnu-nm
    inspect_tool=aarch64-linux-gnu-readelf
    runner=aarch64 ;;
  riscv64-linux-gnu)
    format=elf
    machine=243
    flags=4
    target_cc=riscv64-linux-gnu-gcc
    nm_tool=riscv64-linux-gnu-nm
    inspect_tool=riscv64-linux-gnu-readelf
    runner=riscv64 ;;
  x86_64-windows-gnu)
    format=coff
    machine=0
    flags=0
    target_cc=x86_64-w64-mingw32-gcc
    nm_tool=x86_64-w64-mingw32-nm
    inspect_tool=x86_64-w64-mingw32-objdump
    runner=windows ;;
  *) echo "unsupported static-data target: $target" >&2; exit 2 ;;
esac

run_target() {
  case $runner in
    direct) "$@" ;;
    aarch64) qemu-aarch64 -L "${AARCH64_SYSROOT:-/usr/aarch64-linux-gnu}" "$@" ;;
    riscv64) qemu-riscv64 -L "${RISCV64_SYSROOT:-/usr/riscv64-linux-gnu}" "$@" ;;
    windows) WINEDEBUG=-all wine "$@" ;;
  esac
}

for level in 0 1; do
  "$project_root/pslcc" "-O$level" -c \
    "$project_root/bootstrap/object/static_data.lisp" \
    -o "$work_dir/writer-$level.o"
  cc -std=c11 -Wall -Wextra -Werror \
    "$project_root/tests/harness_bootstrap_static_data_writer.c" \
    "$work_dir/writer-$level.o" -o "$work_dir/writer-$level"
  "$work_dir/writer-$level" "$format" "$work_dir/data-$level.o" \
    "$machine" "$flags"
done

cmp "$work_dir/data-0.o" "$work_dir/data-1.o"
"$nm_tool" -g "$work_dir/data-1.o" | grep -q 'psl_message'
"$nm_tool" -g "$work_dir/data-1.o" | grep -q 'psl_aligned_word'
if "$nm_tool" -g "$work_dir/data-1.o" | grep -q 'psl_hidden_blob'; then
  echo 'local static data symbol escaped global visibility' >&2
  exit 1
fi

case $format in
  elf)
    "$inspect_tool" -S "$work_dir/data-1.o" | grep -q '\.data'
    "$inspect_tool" -sW "$work_dir/data-1.o" | grep -q 'OBJECT.*LOCAL.*psl_hidden_blob'
    "$inspect_tool" -sW "$work_dir/data-1.o" | grep -q 'OBJECT.*GLOBAL.*psl_aligned_word' ;;
  coff)
    "$inspect_tool" -h "$work_dir/data-1.o" | grep -q '\.data'
    "$inspect_tool" -t "$work_dir/data-1.o" | grep -q 'psl_hidden_blob' ;;
esac

suffix=
test "$runner" = windows && suffix=.exe
"$target_cc" -std=c11 -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_static_data.c" \
  "$work_dir/data-1.o" -o "$work_dir/data-check$suffix"
run_target "$work_dir/data-check$suffix"

echo "PSL native static data writer passed for $target"
