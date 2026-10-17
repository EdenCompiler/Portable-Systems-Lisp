#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
case $target in
  x86_64-windows-gnu) platform=windows; nm_tool=x86_64-w64-mingw32-nm ;;
  x86_64-linux-gnu) platform=linux; nm_tool=nm ;;
  aarch64-linux-gnu) platform=linux; nm_tool=aarch64-linux-gnu-nm ;;
  riscv64-linux-gnu) platform=linux; nm_tool=riscv64-linux-gnu-nm ;;
esac
"$target_cc" -O0 -Wall -Wextra -Werror -c \
  "$project_root/runtime/platform_$platform.c" -o "$work_dir/platform.o"

for level in 0 1; do
  source=$project_root/tests/bootstrap_managed_vectors.lisp
  run_compiler_host "$compiler" "-O$level" --profile=hosted --target="$target" \
    "$source" "$work_dir/native.o"
  run_compiler_host "$compiler" "-O$level" --profile=hosted --target="$target" \
    "$source" "$work_dir/repeat.o"
  cmp "$work_dir/native.o" "$work_dir/repeat.o"
  "$nm_tool" -u "$work_dir/native.o" | grep -q psl_rt_push_roots
  "$nm_tool" -u "$work_dir/native.o" | grep -q psl_rt_pop_roots
  "$project_root/pslcc" "-O$level" --profile=hosted --target="$target" \
    -c "$source" -o "$work_dir/seed.o"
  for version in native seed; do
    for c_level in 0 2; do
      "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_managed_vectors.c" \
        "$work_dir/$version.o" "$project_root/runtime/value.c" \
        "$project_root/runtime/cons.c" "$project_root/runtime/string.c" \
        "$project_root/runtime/vector.c" "$project_root/runtime/gc.c" \
        "$project_root/runtime/startup.c" "$work_dir/platform.o" \
        -o "$work_dir/check$target_suffix"
      run_target "$work_dir/check$target_suffix"
    done
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
    for test in native_vectors_api runtime_signatures; do
      "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_$test.c" \
        "$work_dir/$version-core.o" "$work_dir/$version-host.o" \
        -o "$work_dir/api$target_suffix"
      run_target "$work_dir/api$target_suffix"
    done
  done
done
printf 'Native managed VALUE vectors passed (%s)\n' "$target"
