#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
for level in 0 1; do
  for fixture in bootstrap_lexical_duplicate bootstrap_lexical_scope; do
    for version in native seed; do
      for repeat in first second; do
        rm -f "$work_dir/rejected.o"
        if test "$version" = native; then
          if run_compiler_host "$compiler" "-O$level" --target="$target" \
            "$project_root/tests/$fixture.lisp" "$work_dir/rejected.o" \
            >"$work_dir/$repeat.error" 2>&1; then
            echo 'Native compiler accepted invalid lexical bindings' >&2; exit 1
          else
            test "$?" -eq 1
          fi
        elif "$project_root/pslcc" "-O$level" --target="$target" -c \
          "$project_root/tests/$fixture.lisp" -o "$work_dir/rejected.o" \
          >"$work_dir/$repeat.error" 2>&1; then
          echo 'Stage 0 accepted invalid lexical bindings' >&2; exit 1
        else
          test "$?" -eq 1
        fi
        test ! -e "$work_dir/rejected.o"
        test -s "$work_dir/$repeat.error"
      done
      cmp "$work_dir/first.error" "$work_dir/second.error"
    done
  done
  run_compiler_host "$compiler" "-O$level" --target="$target" \
    "$project_root/tests/bootstrap_lexical.lisp" "$work_dir/native.o"
  "$project_root/pslcc" "-O$level" --target="$target" -c \
    "$project_root/tests/bootstrap_lexical.lisp" -o "$work_dir/seed.o"
  for version in native seed; do
    "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
      "$project_root/tests/harness_bootstrap_answer.c" "$work_dir/$version.o" \
      -o "$work_dir/check$target_suffix"
    run_target "$work_dir/check$target_suffix"
  done
done
printf 'Native and Stage 0 lexical validation and nested shadowing passed (%s)\n' "$target"
