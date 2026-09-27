#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

"$project_root/pslcc" -c "$project_root/bootstrap/win64_module.lisp" \
  -o "$work_dir/frame-linux.o"
cc -std=gnu11 -O2 -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_win64_frame.c" \
  "$work_dir/frame-linux.o" -o "$work_dir/check-linux"
"$work_dir/check-linux"

"$project_root/pslcc" --target=x86_64-windows-gnu -c \
  "$project_root/bootstrap/win64_module.lisp" -o "$work_dir/frame-windows.o"
x86_64-w64-mingw32-gcc -std=gnu11 -O2 -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_win64_frame.c" \
  "$work_dir/frame-windows.o" -o "$work_dir/check-windows.exe"
WINEDEBUG=-all wine "$work_dir/check-windows.exe"

"$project_root/pslcc" -c "$project_root/bootstrap/native-core.lisp" \
  -o "$work_dir/core-linux.o"
cc -std=gnu11 -O2 -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_win64_lir.c" \
  "$work_dir/core-linux.o" -o "$work_dir/lir-linux"
"$work_dir/lir-linux"

"$project_root/pslcc" --target=x86_64-windows-gnu -c \
  "$project_root/bootstrap/native-core.lisp" -o "$work_dir/core-windows.o"
x86_64-w64-mingw32-gcc -std=gnu11 -O2 -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_win64_lir.c" \
  "$work_dir/core-windows.o" -o "$work_dir/lir-windows.exe"
WINEDEBUG=-all wine "$work_dir/lir-windows.exe"
