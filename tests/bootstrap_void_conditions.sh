#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
versions=seed
if test -n "$compiler"; then versions="$versions native"; fi
compile_source() {
  if test "$version" = seed; then
    "$project_root/pslcc" "$@"
  else
    run_compiler_host "$compiler" "$@"
  fi
}
for level in 0 1; do
  for version in $versions; do
    # VOID sequences, bindings and results remain valid, and null raw pointers
    # retain Lisp truth. Independently optimized C checks all observable effects.
    compile_source "-O$level" --target="$target" -c \
      "$project_root/tests/bootstrap_void_calls.lisp" -o "$work_dir/valid.o"
    compile_source "-O$level" --target="$target" -c \
      "$project_root/tests/bootstrap_void_calls.lisp" -o "$work_dir/repeat.o"
    cmp "$work_dir/valid.o" "$work_dir/repeat.o"
    for c_level in 0 2; do
      "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_void_calls.c" "$work_dir/valid.o" \
        -o "$work_dir/check$target_suffix"
      run_target "$work_dir/check$target_suffix"
    done
    for profile in freestanding hosted; do
      for name in condition condition-lexical condition-sequence condition-gc; do
        printf 'preserve existing output\n' >"$work_dir/preserved.o"
        cp "$work_dir/preserved.o" "$work_dir/expected"
        if compile_source "-O$level" --target="$target" --profile="$profile" -c \
          "$project_root/tests/bootstrap_void_errors/$name.lisp" \
          -o "$work_dir/preserved.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
          echo "$version accepted VOID IF condition: $name ($profile)" >&2
          exit 1
        else
          test "$?" -eq 1
        fi
        test ! -s "$work_dir/stdout"
        test -s "$work_dir/stderr"
        if test "$version" = seed; then
          if test "$name" != condition-gc || test "$profile" = hosted; then
            grep -q 'IF condition cannot have VOID type' "$work_dir/stderr"
          fi
        fi
        cmp "$work_dir/expected" "$work_dir/preserved.o"
      done
    done
  done
done
printf 'VOID conditions rejected; valid VOID effects and raw-pointer truth preserved (%s)\n' "$target"
