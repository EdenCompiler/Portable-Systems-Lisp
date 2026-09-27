#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
compiler=${PSL_NATIVE_COMPILER:-$project_root/build/pslcc-native}
cross_cc=${AARCH64_CC:-aarch64-linux-gnu-gcc}
sysroot=${AARCH64_SYSROOT:-/usr/aarch64-linux-gnu}

run_aarch64() {
  qemu-aarch64 -L "$sysroot" "$@"
}

check_fixture() {
  name=$1
  level=$2
  extra=
  case $name in
    foreign_calls) extra="$project_root/tests/bootstrap_foreign_calls.c" ;;
  esac
  "$compiler" "-O$level" --target=aarch64-linux-gnu \
    "$project_root/tests/bootstrap_$name.lisp" "$work_dir/$name-$level.o"
  "$compiler" --target=aarch64-linux-gnu "-O$level" \
    "$project_root/tests/bootstrap_$name.lisp" "$work_dir/$name-$level-repeat.o"
  cmp "$work_dir/$name-$level.o" "$work_dir/$name-$level-repeat.o"
  readelf -h "$work_dir/$name-$level.o" | grep -q AArch64
  "$cross_cc" -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_$name.c" \
    $extra "$work_dir/$name-$level.o" -o "$work_dir/$name-$level"
  run_aarch64 "$work_dir/$name-$level"
  "$project_root/pslcc" "-O$level" --target=aarch64-linux-gnu -c \
    "$project_root/tests/bootstrap_$name.lisp" -o "$work_dir/reference.o"
  "$cross_cc" -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_$name.c" \
    $extra "$work_dir/reference.o" -o "$work_dir/reference"
  run_aarch64 "$work_dir/reference"
}

for level in 0 1; do
  for name in answer two_functions local_calls six_arguments usize integer_types \
      mixed_integers bitops pointers stack_arguments foreign_calls void_calls \
      layout_queries optimizer cfg_optimizer effects inline aarch64_arguments; do
    check_fixture "$name" "$level"
  done
done
readelf -r "$work_dir/foreign_calls-1.o" | grep -q R_AARCH64_CALL26
readelf -s "$work_dir/foreign_calls-1.o" | grep -q '\$x'
if nm -u "$work_dir/cfg_optimizer-1.o" | grep -q cfg_dead; then
  echo 'AArch64 output retained an unreachable import' >&2
  exit 1
fi
# Verify the same imported calls in a shared-library link.
"$cross_cc" -shared "$project_root/tests/bootstrap_foreign_calls.c" \
  "$work_dir/foreign_calls-1.o" -o "$work_dir/libforeign.so"
"$cross_cc" "$project_root/tests/harness_bootstrap_foreign_calls.c" \
  -L"$work_dir" -lforeign -Wl,-rpath,"$work_dir" -o "$work_dir/shared"
run_aarch64 "$work_dir/shared"

compile_modules() {
  generation=$1
  for pair in core:bootstrap/native-core.lisp host:bootstrap/host/driver.lisp \
      source:bootstrap/host/source_unit.lisp driver:bootstrap/host/compiler.lisp; do
    name=${pair%%:*}
    source=${pair#*:}
    if test "$generation" -eq 1; then
      "$compiler" --target=aarch64-linux-gnu "$project_root/$source" "$work_dir/$name-$generation.o"
    else
      run_aarch64 "$work_dir/compiler-$((generation - 1))" --target=aarch64-linux-gnu \
        "$project_root/$source" "$work_dir/$name-$generation.o"
      cmp "$work_dir/$name-1.o" "$work_dir/$name-$generation.o"
    fi
  done
  test "$(nm -u "$work_dir/core-$generation.o" | wc -l)" -eq 0
  "$cross_cc" -Wall -Wextra -Werror "$project_root/bootstrap/driver.c" \
    "$project_root/bootstrap/host/source.c" "$project_root/bootstrap/host/compiler.c" \
    "$work_dir/core-$generation.o" "$work_dir/host-$generation.o" \
    "$work_dir/source-$generation.o" "$work_dir/driver-$generation.o" \
    -o "$work_dir/compiler-$generation"
}

# Rebuild all four PSL modules on the target, then compare artifacts from
# successive native subset generations. This is not the complete M8 gate.
for generation in 1 2 3; do
  compile_modules "$generation"
  for name in stack_arguments foreign_calls cfg_optimizer inline aarch64_arguments; do
    run_aarch64 "$work_dir/compiler-$generation" --target=aarch64-linux-gnu \
      "$project_root/tests/bootstrap_$name.lisp" "$work_dir/target-$name.o"
    cmp "$work_dir/$name-1.o" "$work_dir/target-$name.o"
  done
  # An AArch64 compiler host must still generate identical x86-64 output.
  "$compiler" "$project_root/tests/bootstrap_stack_arguments.lisp" "$work_dir/x86-reference.o"
  run_aarch64 "$work_dir/compiler-$generation" "$project_root/tests/bootstrap_stack_arguments.lisp" \
    "$work_dir/x86-target.o"
  cmp "$work_dir/x86-reference.o" "$work_dir/x86-target.o"
done

echo 'PSL native AArch64 output, C interoperability, and subset generations passed'
