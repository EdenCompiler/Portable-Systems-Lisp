#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
compiler=${PSL_NATIVE_COMPILER:-$project_root/pslcc}
runtime_sources="$project_root/runtime/value.c $project_root/runtime/cons.c $project_root/runtime/string.c $project_root/runtime/symbol.c $project_root/runtime/package.c $project_root/runtime/closure.c $project_root/runtime/vector.c $project_root/runtime/values.c $project_root/runtime/gc.c $project_root/runtime/startup.c"
cc -O0 -std=c11 -Wall -Wextra -Werror -c \
  "$project_root/runtime/platform_linux.c" -o "$work_dir/runtime-platform.o"

for level in 0 1; do
  "$compiler" "-O$level" --target=x86_64-linux-gnu --profile=hosted -c \
    "$project_root/bootstrap/native-core.lisp" \
    -o "$work_dir/native-core-O$level.o"
  cc -Wall -Wextra -Werror \
    "$project_root/tests/harness_bootstrap_modules.c" \
    "$work_dir/native-core-O$level.o" \
    $runtime_sources "$work_dir/runtime-platform.o" \
    -o "$work_dir/native-core-O$level"
  "$work_dir/native-core-O$level"
done

"$compiler" -O1 --target=x86_64-linux-gnu --profile=hosted -c \
  "$project_root/bootstrap/native-core.lisp" -o "$work_dir/repeat.o"
cmp "$work_dir/native-core-O1.o" "$work_dir/repeat.o"

"$compiler" --target=x86_64-linux-gnu --profile=hosted -c "$project_root/tests/include/entry.lisp" \
  -o "$work_dir/include.o"
cc -Wall -Wextra -Werror "$project_root/tests/include/harness.c" \
  "$work_dir/include.o" -o "$work_dir/include-harness"
"$work_dir/include-harness"

echo 'PSL bootstrap module inclusion passed'
