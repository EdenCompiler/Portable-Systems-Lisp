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
 source=$project_root/tests/bootstrap_word_aggregates.lisp
 run_compiler_host "$compiler" "-O$level" --target="$target" --profile=freestanding "$source" "$work_dir/native.o"
 run_compiler_host "$compiler" "-O$level" --target="$target" --profile=freestanding "$source" "$work_dir/repeat.o"
 cmp "$work_dir/native.o" "$work_dir/repeat.o"
 "$project_root/pslcc" "-O$level" --target="$target" --profile=freestanding -c "$source" -o "$work_dir/seed.o"
 for version in native seed; do
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_word_aggregates.c" "$work_dir/$version.o" -o "$work_dir/check$target_suffix"
  run_target "$work_dir/check$target_suffix"
 done
 bootstrap_fixture_compile native "$compiler" "$level" "$target" hosted \
  "$project_root/bootstrap/native-core.lisp" "$work_dir/native-core.o"
 bootstrap_fixture_compile native "$compiler" "$level" "$target" hosted \
  "$project_root/bootstrap/host/driver.lisp" "$work_dir/native-host.o"
 bootstrap_fixture_compile seed "$project_root/pslcc" "$level" "$target" hosted \
  "$project_root/bootstrap/native-core.lisp" "$work_dir/seed-core.o"
 bootstrap_fixture_compile seed "$project_root/pslcc" "$level" "$target" hosted \
  "$project_root/bootstrap/host/driver.lisp" "$work_dir/seed-host.o"
 for version in native seed; do
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_word_aggregates_api.c" "$work_dir/$version-core.o" "$work_dir/$version-host.o" -o "$work_dir/api$target_suffix"
  run_target "$work_dir/api$target_suffix"
 done
done
printf 'Native one-word C aggregates passed (%s)\n' "$target"
