#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
 . "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
suffix=$target_suffix
if test "$compiler" = "$project_root/build/pslcc-native" && test -n "$compiler_host_suffix"; then
  compiler=$compiler$compiler_host_suffix
fi
# The compiler runs on the host; its selected output is checked by target C.
for level in 0 1; do
  run_compiler_host "$compiler" "-O$level" --target="$target" \
    "$project_root/tests/bootstrap_pointer_qualifiers.lisp" "$work_dir/native.o"
  run_compiler_host "$compiler" "-O$level" --target="$target" \
    "$project_root/tests/bootstrap_pointer_qualifiers.lisp" "$work_dir/repeat.o"
  cmp "$work_dir/native.o" "$work_dir/repeat.o"
  "$project_root/pslcc" "-O$level" --target="$target" -c \
    "$project_root/tests/bootstrap_pointer_qualifiers.lisp" -o "$work_dir/stage0.o"
  for version in native stage0; do
    "$target_cc" -std=c11 -Wall -Wextra -Werror \
      "$project_root/tests/harness_bootstrap_pointer_qualifiers.c" \
      "$work_dir/$version.o" -o "$work_dir/check$suffix"
    run_target "$work_dir/check$suffix"
  done
  for source in "$project_root"/tests/bootstrap_pointer_qualifier_errors/*.lisp \
      "$project_root/tests/bootstrap_pointer_errors/qualifier.lisp"; do
    if run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$work_dir/rejected.o" \
        >"$work_dir/native.out" 2>"$work_dir/native.err"; then
      echo "native compiler accepted invalid qualifiers: $source" >&2
      exit 1
    fi
    test ! -e "$work_dir/rejected.o"
    if "$project_root/pslcc" "-O$level" --target="$target" -c "$source" \
        -o "$work_dir/rejected.o" >"$work_dir/stage0.out" 2>"$work_dir/stage0.err"; then
      echo "Stage 0 accepted invalid qualifiers: $source" >&2
      exit 1
    fi
    test ! -e "$work_dir/rejected.o"
  done
done
printf 'native pointer qualifiers passed (%s)\n' "$target"
