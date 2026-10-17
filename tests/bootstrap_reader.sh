#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
case ${1:-} in
  x86_64-linux-gnu|aarch64-linux-gnu|riscv64-linux-gnu|x86_64-windows-gnu)
    native_compiler=$project_root/pslcc
    target=$1 ;;
  *)
    native_compiler=${1:-$project_root/pslcc}
    target=${2:-x86_64-linux-gnu} ;;
esac
. "$project_root/tests/bootstrap_target.sh"
select_bootstrap_target

for level in 0 1; do
  "$native_compiler" --target="$target" "-O$level" -c \
    "$project_root/bootstrap/frontend/reader.lisp" -o "$work_dir/reader-O$level.o"
  "$compiler" -Wall -Wextra -Werror \
    "$project_root/tests/harness_bootstrap_reader.c" \
    "$work_dir/reader-O$level.o" -o "$work_dir/reader-O$level$suffix"
  case $target in
    x86_64-windows-gnu)
      run_harness "$work_dir/reader-O$level$suffix" ;;
    *)
      run_harness "$work_dir/reader-O$level$suffix" \
        "$project_root"/examples/*/*.lisp ;;
  esac
done

"$native_compiler" --target="$target" -O1 -c \
  "$project_root/bootstrap/frontend/reader.lisp" -o "$work_dir/repeat.o"
cmp "$work_dir/reader-O1.o" "$work_dir/repeat.o"

echo "PSL bootstrap reader module passed on $target"
