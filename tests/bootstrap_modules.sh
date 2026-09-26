#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

for level in 0 1; do
  "$project_root/pslcc" "-O$level" -c \
    "$project_root/bootstrap/native-core.lisp" \
    -o "$work_dir/native-core-O$level.o"
  cc -Wall -Wextra -Werror \
    "$project_root/tests/harness_bootstrap_modules.c" \
    "$work_dir/native-core-O$level.o" \
    -o "$work_dir/native-core-O$level"
  "$work_dir/native-core-O$level"
done

"$project_root/pslcc" -O1 -c \
  "$project_root/bootstrap/native-core.lisp" -o "$work_dir/repeat.o"
cmp "$work_dir/native-core-O1.o" "$work_dir/repeat.o"

"$project_root/pslcc" -c "$project_root/tests/include/entry.lisp" \
  -o "$work_dir/include.o"
cc -Wall -Wextra -Werror "$project_root/tests/include/harness.c" \
  "$work_dir/include.o" -o "$work_dir/include-harness"
"$work_dir/include-harness"

echo 'PSL bootstrap module inclusion passed'
