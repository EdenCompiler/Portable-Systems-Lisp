#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
target=${1:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
suffix=$target_suffix
for level in 0 1; do
  "$project_root/pslcc" "-O$level" --target="$target" -c \
    "$project_root/tests/bootstrap_packed.lisp" -o "$work_dir/stage0-$level.o"
  run_compiler_host "$native_compiler" "-O$level" --target="$target" \
    "$project_root/tests/bootstrap_packed.lisp" "$work_dir/native-$level.o"
  run_compiler_host "$native_compiler" "-O$level" --target="$target" \
    "$project_root/tests/bootstrap_packed.lisp" "$work_dir/repeat-$level.o"
  cmp "$work_dir/native-$level.o" "$work_dir/repeat-$level.o"
  for compiler in stage0 native; do
    test -z "$(nm -u "$work_dir/$compiler-$level.o")"
    "$target_cc" -std=c11 -Wall -Wextra -Werror \
      "$project_root/tests/harness_bootstrap_packed.c" \
      "$work_dir/$compiler-$level.o" -o "$work_dir/$compiler-$level$suffix"
    run_target "$work_dir/$compiler-$level$suffix"
  done
done
for source in "$project_root"/tests/bootstrap_packed_errors/*.lisp; do
  rm -f "$work_dir/rejected.o"
  if run_compiler_host "$native_compiler" --target="$target" "$source" "$work_dir/rejected.o" \
      >"$work_dir/rejected.log" 2>&1; then
    echo "native accepted invalid packed layout: $source" >&2; exit 1
  fi
  test ! -e "$work_dir/rejected.o"
  if "$project_root/pslcc" --target="$target" -c "$source" \
      -o "$work_dir/rejected.o" >"$work_dir/rejected.log" 2>&1; then
    echo "Stage 0 accepted invalid packed layout: $source" >&2; exit 1
  fi
  test ! -e "$work_dir/rejected.o"
done
echo "PSL packed layout, nested offsets and unaligned memory checks passed for $target"
