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
  source=$project_root/bootstrap/frontend/package_forms.lisp
  run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$work_dir/native.o"
  "$project_root/pslcc" "-O$level" --target="$target" -c "$source" -o "$work_dir/stage0.o"
  for version in native stage0; do
    "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
      "$project_root/tests/harness_bootstrap_package_form_edges.c" "$work_dir/$version.o" \
      -o "$work_dir/check$target_suffix"
    run_target "$work_dir/check$target_suffix"
  done
  source=$project_root/tests/bootstrap_package_form_edges.lisp
  if "$project_root/pslcc" "-O$level" --target="$target" -c "$source" -o "$work_dir/invalid.o" >"$work_dir/out" 2>"$work_dir/err"; then
    echo "Stage 0 treated the keyword :EOF as end of input" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid.o"
  if run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$work_dir/invalid.o" >"$work_dir/out" 2>"$work_dir/err"; then
    echo "native compiler accepted the invalid keyword source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid.o"
done
echo "source reader and package API boundary checks passed ($target)"
