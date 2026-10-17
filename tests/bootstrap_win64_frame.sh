#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
native_compiler=${1:-$project_root/pslcc}
target=${2:-x86_64-windows-gnu}
if test "$target" != x86_64-windows-gnu; then
  echo "Win64 unwind gate requires x86_64-windows-gnu, got $target" >&2
  exit 2
fi
runtime_sources="$project_root/runtime/value.c $project_root/runtime/cons.c $project_root/runtime/string.c $project_root/runtime/symbol.c $project_root/runtime/package.c $project_root/runtime/closure.c $project_root/runtime/vector.c $project_root/runtime/values.c $project_root/runtime/gc.c $project_root/runtime/startup.c"
cc -O0 -std=gnu11 -Wall -Wextra -Werror -c \
  "$project_root/runtime/platform_linux.c" -o "$work_dir/platform-linux.o"
x86_64-w64-mingw32-gcc -O0 -std=gnu11 -Wall -Wextra -Werror -c \
  "$project_root/runtime/platform_windows.c" -o "$work_dir/platform-windows.o"

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

"$project_root/pslcc" --profile=hosted -c "$project_root/bootstrap/native-core.lisp" \
  -o "$work_dir/core-linux.o"
cc -std=gnu11 -O2 -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_win64_lir.c" \
  "$work_dir/core-linux.o" $runtime_sources "$work_dir/platform-linux.o" \
  -o "$work_dir/lir-linux"
"$work_dir/lir-linux"

"$project_root/pslcc" --profile=hosted --target=x86_64-windows-gnu -c \
  "$project_root/bootstrap/native-core.lisp" -o "$work_dir/core-windows.o"
x86_64-w64-mingw32-gcc -std=gnu11 -O2 -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_win64_lir.c" \
  "$work_dir/core-windows.o" $runtime_sources "$work_dir/platform-windows.o" \
  -o "$work_dir/lir-windows.exe"
WINEDEBUG=-all wine "$work_dir/lir-windows.exe"

# Repeat the large-frame and partial-unwind checks using the compiler supplied
# by the current release stage. The Stage 0 checks above remain the baseline.
"$native_compiler" --target="$target" -c \
  "$project_root/bootstrap/win64_module.lisp" -o "$work_dir/frame-stage.o"
x86_64-w64-mingw32-gcc -std=gnu11 -O2 -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_win64_frame.c" \
  "$work_dir/frame-stage.o" -o "$work_dir/check-stage.exe"
WINEDEBUG=-all wine "$work_dir/check-stage.exe"

"$native_compiler" --profile=hosted --target="$target" -c \
  "$project_root/bootstrap/native-core.lisp" -o "$work_dir/core-stage.o"
x86_64-w64-mingw32-gcc -std=gnu11 -O2 -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_win64_lir.c" \
  "$work_dir/core-stage.o" $runtime_sources "$work_dir/platform-windows.o" \
  -o "$work_dir/lir-stage.exe"
WINEDEBUG=-all wine "$work_dir/lir-stage.exe"
echo 'PSL Win64 large-frame/unwind tests passed'
