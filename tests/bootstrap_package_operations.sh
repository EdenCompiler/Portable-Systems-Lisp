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
sbcl --script tests/bootstrap_package_operations_oracle.lisp
for level in 0 1; do
  source=$project_root/bootstrap/frontend/environment/operations.lisp
  run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$work_dir/native.o"
  run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$work_dir/repeat.o"
  cmp "$work_dir/native.o" "$work_dir/repeat.o"
  "$project_root/pslcc" "-O$level" --target="$target" -c "$source" -o "$work_dir/stage0.o"
  for version in native stage0; do
    for buckets in 0 1 1024; do
      "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror -DTEST_BUCKET_COUNT="$buckets" \
        "$project_root/tests/harness_bootstrap_package_operations.c" "$work_dir/$version.o" \
        -o "$work_dir/check$target_suffix"
      run_target "$work_dir/check$target_suffix"
    done
  done
done
echo "native package transaction checks passed ($target)"
