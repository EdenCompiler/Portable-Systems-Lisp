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
  for unit in native-core host/driver; do
    name=${unit##*/}
    source=$project_root/bootstrap/$unit.lisp
    bootstrap_fixture_compile native "$compiler" "$level" "$target" hosted \
      "$source" "$work_dir/native-$name.o"
    bootstrap_fixture_compile seed "$project_root/pslcc" "$level" "$target" hosted \
      "$source" "$work_dir/seed-$name.o"
  done
  for version in native seed; do
    for c_level in 0 2; do
      for fixture in ir_dump ir_unit; do
      "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_$fixture.c" \
        "$work_dir/$version-native-core.o" "$work_dir/$version-driver.o" \
        -o "$work_dir/check$target_suffix"
      run_target "$work_dir/check$target_suffix"
      done
    done
  done
done
printf 'Verified native IR text and caller-owned output passed (%s)\n' "$target"
