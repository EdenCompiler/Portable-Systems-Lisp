#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
case $target in x86_64-linux-gnu) target_id=0 ;; aarch64-linux-gnu) target_id=1 ;; riscv64-linux-gnu) target_id=2 ;; x86_64-windows-gnu) target_id=3 ;; esac
case $compiler_host_target in
 x86_64-linux-gnu) host_cc=${CC:-cc}; host_platform=linux ;;
 x86_64-windows-gnu) host_cc=${WINDOWS_CC:-x86_64-w64-mingw32-gcc}; host_platform=windows ;;
 aarch64-linux-gnu) host_cc=${AARCH64_CC:-aarch64-linux-gnu-gcc}; host_platform=linux ;;
 riscv64-linux-gnu) host_cc=${RISCV64_CC:-riscv64-linux-gnu-gcc}; host_platform=linux ;;
esac
"$host_cc" -O0 -std=c11 -Wall -Wextra -Werror \
 -c "$project_root/runtime/platform_$host_platform.c" -o "$work_dir/host-platform.o"
runtime_sources=
for module in value cons string symbol package closure vector values gc startup; do
 runtime_sources="$runtime_sources $project_root/runtime/$module.c"
done
for level in 0 1; do
 bootstrap_fixture_compile native "$compiler" "$level" "$compiler_host_target" hosted \
  "$project_root/bootstrap/native-core.lisp" "$work_dir/native-core.o"
 bootstrap_fixture_compile native "$compiler" "$level" "$compiler_host_target" hosted \
  "$project_root/bootstrap/host/driver.lisp" "$work_dir/native-host.o"
 bootstrap_fixture_compile seed "$project_root/pslcc" "$level" "$compiler_host_target" hosted \
  "$project_root/bootstrap/native-core.lisp" "$work_dir/seed-core.o"
 bootstrap_fixture_compile seed "$project_root/pslcc" "$level" "$compiler_host_target" hosted \
  "$project_root/bootstrap/host/driver.lisp" "$work_dir/seed-host.o"
 for version in native seed; do
  # Hosted compiler API receivers link the complete runtime explicitly.
  # shellcheck disable=SC2086
  "$host_cc" -O2 -std=c11 -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_function_addresses_api.c" "$work_dir/$version-core.o" "$work_dir/$version-host.o" $runtime_sources "$work_dir/host-platform.o" -o "$work_dir/generate$compiler_host_suffix"
  for far in 0 1; do
   run_compiler_host "$work_dir/generate$compiler_host_suffix" "$target_id" "$level" "$far" "$work_dir/address.o"
   run_compiler_host "$work_dir/generate$compiler_host_suffix" "$target_id" "$level" "$far" "$work_dir/repeat.o"
   cmp "$work_dir/address.o" "$work_dir/repeat.o"
   for c_level in 0 2; do
    "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_function_addresses.c" "$work_dir/address.o" -o "$work_dir/check$target_suffix"
    run_target "$work_dir/check$target_suffix"
   done
  done
 done
done
printf 'Defined function addresses, capacity, receiver and large-text execution passed (%s)\n' "$target"
