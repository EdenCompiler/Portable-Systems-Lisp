#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
target=${1:-x86_64-linux-gnu}
suffix=
case $target in
  x86_64-linux-gnu) compiler=cc ;;
  x86_64-windows-gnu) compiler=x86_64-w64-mingw32-gcc; suffix=.exe ;;
  aarch64-linux-gnu) compiler=aarch64-linux-gnu-gcc ;;
  riscv64-linux-gnu) compiler=riscv64-linux-gnu-gcc ;;
  *) echo "unsupported layout query test target: $target" >&2; exit 2 ;;
esac

run_target() {
  case $target in
    x86_64-linux-gnu) "$@" ;;
    x86_64-windows-gnu) WINEDEBUG=-all wine "$@" ;;
    aarch64-linux-gnu) qemu-aarch64 -L "${AARCH64_SYSROOT:-/usr/aarch64-linux-gnu}" "$@" ;;
    riscv64-linux-gnu) qemu-riscv64 -L "${RISCV64_SYSROOT:-/usr/riscv64-linux-gnu}" "$@" ;;
  esac
}

for level in 0 1; do
  "$project_root/pslcc" "-O$level" --target="$target" -c \
    "$project_root/tests/bootstrap_layout_queries.lisp" -o "$work_dir/query-$level.o"
  test -z "$(nm -u "$work_dir/query-$level.o")"
  "$compiler" -Wall -Wextra -Werror \
    "$project_root/tests/harness_bootstrap_layout_queries.c" \
    "$work_dir/query-$level.o" -o "$work_dir/query-$level$suffix"
  run_target "$work_dir/query-$level$suffix"
  "$project_root/pslcc" "-O$level" --target="$target" -c \
    "$project_root/tests/bootstrap_layout_queries.lisp" -o "$work_dir/repeat-$level.o"
  cmp "$work_dir/query-$level.o" "$work_dir/repeat-$level.o"
done
for source in "$project_root"/tests/bootstrap_query_errors/*.lisp; do
  if "$project_root/pslcc" --target="$target" -c "$source" \
      -o "$work_dir/invalid.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "Stage 0 accepted invalid layout/address source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid.o"
done
echo "PSL layout/address queries passed on $target"
