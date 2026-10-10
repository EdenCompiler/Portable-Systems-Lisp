#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
# Each unknown imported call is observable; the large frame survives both levels.
{
  echo '(ffi:import-function "frame_tick" ((value u64) (index u64)) -> u64)'
  echo '(defun large_frame (value)'
  echo ' (declare (type u64 value) (returns u64) (c-export :c))'
  echo ' (let ('
  awk 'BEGIN { for (i=0;i<400;i++) printf "(v%d (ffi:call frame_tick value %d))\n", i,i }'
  echo ')'
  awk 'BEGIN { for(i=0;i<399;i++) printf "(wrap+ v%d ",i; printf "v399"; for(i=0;i<399;i++) printf ")"; print "))" }'
} > "$work_dir/large.lisp"
for level in 0 1; do
  "$project_root/pslcc" --target=x86_64-windows-gnu "-O$level" -c \
    "$project_root/examples/basic/standalone.lisp" -o "$work_dir/small.o"
  "$project_root/pslcc" --target=x86_64-windows-gnu "-O$level" -c \
    "$work_dir/large.lisp" -o "$work_dir/large.o"
  "$project_root/pslcc" --target=x86_64-windows-gnu "-O$level" -c \
    "$work_dir/large.lisp" -o "$work_dir/repeat.o"
  cmp "$work_dir/large.o" "$work_dir/repeat.o"
  x86_64-w64-mingw32-gcc -O0 -Wall -Wextra -Werror -DPSL_WINDOWS_FRAME_GATE \
    "$project_root/tests/harness_windows_unwind.c" "$work_dir/small.o" \
    "$work_dir/large.o" -o "$work_dir/check.exe"
  WINEDEBUG=-all wine "$work_dir/check.exe"
done
