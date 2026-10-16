#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
cd "$project_root"
sbcl --script tests/bootstrap_cl_user_oracle.lisp
for level in 0 1; do
  source=$project_root/tests/bootstrap_cl_user.lisp
  run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$source" "$work_dir/native.o"
  run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$source" "$work_dir/native-repeat.o"
  cmp "$work_dir/native.o" "$work_dir/native-repeat.o"
  "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted -c "$source" -o "$work_dir/stage0.o"
  for version in native stage0; do
    for c_level in 0 2; do
    "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
      "$project_root/tests/harness_bootstrap_cl_user.c" "$work_dir/$version.o" \
      -o "$work_dir/check$target_suffix"
    run_target "$work_dir/check$target_suffix"
    done
  done
  for version in native stage0; do
    for repeat in first second; do
      rm -f "$work_dir/rejected.o"
      if [ "$version" = native ]; then
        if run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted \
          "$project_root/tests/bootstrap_cl_user_bad.lisp" "$work_dir/rejected.o" \
          >"$work_dir/$version-$repeat.error" 2>&1; then
          echo "native compiler accepted a non-imported PSL name in CL-USER" >&2; exit 1
        else
          status=$?; test "$status" -eq 1
        fi
      else
        if "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted -c \
          "$project_root/tests/bootstrap_cl_user_bad.lisp" -o "$work_dir/rejected.o" \
          >"$work_dir/$version-$repeat.error" 2>&1; then
          echo "Stage 0 accepted a non-imported PSL name in CL-USER" >&2; exit 1
        else
          status=$?; test "$status" -eq 1
        fi
      fi
      test ! -e "$work_dir/rejected.o"
    done
    cmp "$work_dir/$version-first.error" "$work_dir/$version-second.error"
  done
done
printf 'CL-USER native/Stage 0 package parity passed (%s)\n' "$target"
