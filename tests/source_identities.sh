#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
target=${1:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
for level in 0 1; do
  "$project_root/pslcc" "-O$level" --target="$target" -c \
    "$project_root/tests/source_identities.lisp" -o "$work_dir/identities.o"
  "$project_root/pslcc" "-O$level" --target="$target" -c \
    "$project_root/tests/source_identities.lisp" -o "$work_dir/repeat.o"
  cmp "$work_dir/identities.o" "$work_dir/repeat.o"
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
    "$project_root/tests/harness_source_identities.c" "$work_dir/identities.o" \
    -o "$work_dir/check$target_suffix"
  run_target "$work_dir/check$target_suffix"
  "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted \
    "$project_root/tests/source_identities_managed.lisp" -o "$work_dir/managed$target_suffix"
  run_target "$work_dir/managed$target_suffix"
  for source in "$project_root"/tests/bootstrap_reader_identity_errors/*.lisp; do
    rm -f "$work_dir/rejected.o"
    if "$project_root/pslcc" "-O$level" --target="$target" -c "$source" \
        -o "$work_dir/rejected.o" >"$work_dir/rejected.out" 2>"$work_dir/rejected.err"; then
      echo "Stage 0 accepted a distinct source symbol: $source" >&2
      exit 1
    fi
    test ! -e "$work_dir/rejected.o"
    test -s "$work_dir/rejected.err"
  done
done
echo "Stage 0 source identities, lexical shadowing, closures and multiple values passed ($target)"
