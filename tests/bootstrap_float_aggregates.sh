#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
case $target in x86_64-windows-gnu) platform=windows ;; *) platform=linux ;; esac
"$target_cc" -O0 -std=c11 -Wall -Wextra -Werror -c "$project_root/runtime/platform_$platform.c" -o "$work_dir/platform.o"
for level in 0 1; do
 source=$project_root/tests/bootstrap_float_aggregates.lisp
 run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$source" "$work_dir/native.o"
 run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$source" "$work_dir/repeat.o"
 cmp "$work_dir/native.o" "$work_dir/repeat.o"
 "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted -c "$source" -o "$work_dir/seed.o"
 for version in native seed; do
  for c_level in 0 2; do
   "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_float_aggregates.c" "$work_dir/$version.o" "$project_root/runtime/value.c" "$project_root/runtime/string.c" "$project_root/runtime/gc.c" "$project_root/runtime/startup.c" "$work_dir/platform.o" -o "$work_dir/check$target_suffix"
   run_target "$work_dir/check$target_suffix"
  done
 done
 run_compiler_host "$compiler" "-O$level" --target="$target" "$project_root/bootstrap/native-core.lisp" "$work_dir/native-core.o"
 run_compiler_host "$compiler" "-O$level" --target="$target" "$project_root/bootstrap/host/driver.lisp" "$work_dir/native-host.o"
 "$project_root/pslcc" "-O$level" --target="$target" -c "$project_root/bootstrap/native-core.lisp" -o "$work_dir/seed-core.o"
 "$project_root/pslcc" "-O$level" --target="$target" -c "$project_root/bootstrap/host/driver.lisp" -o "$work_dir/seed-host.o"
 for version in native seed; do
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_float_aggregates_api.c" "$work_dir/$version-core.o" "$work_dir/$version-host.o" -o "$work_dir/api$target_suffix"
  run_target "$work_dir/api$target_suffix"
 done
done
printf 'Native floating/mixed C aggregates through 16 bytes passed (%s)\n' "$target"
