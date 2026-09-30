#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
compiler=${PSL_NATIVE_COMPILER:-$project_root/build/pslcc-native}
target=${1:?expected aarch64-linux-gnu or riscv64-linux-gnu}
case $target in
  aarch64-linux-gnu)
    cross_cc=${AARCH64_CC:-aarch64-linux-gnu-gcc}
    sysroot=${AARCH64_SYSROOT:-/usr/aarch64-linux-gnu}
    emulator=qemu-aarch64
    machine=AArch64
    relocation=R_AARCH64_CALL26 ;;
  riscv64-linux-gnu)
    cross_cc=${RISCV64_CC:-riscv64-linux-gnu-gcc}
    sysroot=${RISCV64_SYSROOT:-/usr/riscv64-linux-gnu}
    emulator=qemu-riscv64
    machine=RISC-V
    relocation=R_RISCV_CALL_PLT ;;
  *) echo "unsupported native output gate target: $target" >&2; exit 2 ;;
esac

run_target() {
  "$emulator" -L "$sysroot" "$@"
}

check_fixture() {
  name=$1
  level=$2
  extra=
  case $name in
    foreign_calls) extra="$project_root/tests/bootstrap_foreign_calls.c" ;;
  esac
  "$compiler" "-O$level" --target="$target" \
    "$project_root/tests/bootstrap_$name.lisp" "$work_dir/$name-$level.o"
  "$compiler" --target="$target" "-O$level" \
    "$project_root/tests/bootstrap_$name.lisp" "$work_dir/$name-$level-repeat.o"
  cmp "$work_dir/$name-$level.o" "$work_dir/$name-$level-repeat.o"
  readelf -h "$work_dir/$name-$level.o" | grep -q "$machine"
  "$cross_cc" -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_$name.c" \
    $extra "$work_dir/$name-$level.o" -o "$work_dir/$name-$level"
  run_target "$work_dir/$name-$level"
  "$project_root/pslcc" "-O$level" --target="$target" -c \
    "$project_root/tests/bootstrap_$name.lisp" -o "$work_dir/reference.o"
  "$cross_cc" -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_$name.c" \
    $extra "$work_dir/reference.o" -o "$work_dir/reference"
  run_target "$work_dir/reference"
}

for level in 0 1; do
  for name in answer two_functions local_calls six_arguments usize integer_types \
      mixed_integers bitops pointers stack_arguments foreign_calls void_calls \
      layout_queries optimizer cfg_optimizer effects inline integer_stack_ffi \
      data_import; do
    check_fixture "$name" "$level"
  done
  if test "$target" = riscv64-linux-gnu; then
    check_fixture riscv64_abi "$level"
  fi
done
readelf -r "$work_dir/foreign_calls-1.o" | grep -q "$relocation"
if test "$target" = aarch64-linux-gnu; then
  readelf -s "$work_dir/foreign_calls-1.o" | grep -q '\$x'
  test "$(readelf -r "$work_dir/data_import-1.o" | grep -c R_AARCH64_ADR_GOT)" -eq 5
  test "$(readelf -r "$work_dir/data_import-1.o" | grep -c R_AARCH64_LD64_GO)" -eq 5
else
  readelf -h "$work_dir/foreign_calls-1.o" | grep -q 'double-float ABI'
  test "$(readelf -r "$work_dir/data_import-1.o" | grep -c R_RISCV_GOT_HI20)" -eq 5
  test "$(readelf -r "$work_dir/data_import-1.o" | grep -c R_RISCV_PCREL_LO1)" -eq 5
  if readelf -r "$work_dir/foreign_calls-1.o" | grep -q R_RISCV_RELAX; then
    echo 'native RISC-V output permits code-shifting relaxation' >&2
    exit 1
  fi
fi
if nm -u "$work_dir/data_import-1.o" | grep -q unused_counter; then
  echo 'native ELF output retained an unused data import' >&2
  exit 1
fi
if nm -u "$work_dir/cfg_optimizer-1.o" | grep -q cfg_dead; then
  echo 'native output retained an unreachable import' >&2
  exit 1
fi
# Verify the same imported calls through static and shared libraries.
"$cross_cc" -c "$project_root/tests/bootstrap_foreign_calls.c" -o "$work_dir/provider.o"
ar rcs "$work_dir/libforeign.a" "$work_dir/foreign_calls-1.o" "$work_dir/provider.o"
"$cross_cc" "$project_root/tests/harness_bootstrap_foreign_calls.c" \
  "$work_dir/libforeign.a" -o "$work_dir/static-library"
run_target "$work_dir/static-library"
"$cross_cc" -shared "$project_root/tests/bootstrap_foreign_calls.c" \
  "$work_dir/foreign_calls-1.o" -o "$work_dir/libforeign.so"
"$cross_cc" "$project_root/tests/harness_bootstrap_foreign_calls.c" \
  -L"$work_dir" -lforeign -Wl,-rpath,"$work_dir" -o "$work_dir/shared"
run_target "$work_dir/shared"

compile_modules() {
  generation=$1
  for pair in core:bootstrap/native-core.lisp host:bootstrap/host/driver.lisp \
      source:bootstrap/host/source_unit.lisp driver:bootstrap/host/compiler.lisp \
      input:bootstrap/host/source_io.lisp path:bootstrap/host/source_path_posix.lisp \
      output:bootstrap/host/output.lisp; do
    name=${pair%%:*}
    source=${pair#*:}
    if test "$generation" -eq 1; then
      "$compiler" --target="$target" "$project_root/$source" "$work_dir/$name-$generation.o"
    else
      run_target "$work_dir/compiler-$((generation - 1))" --target="$target" \
        "$project_root/$source" "$work_dir/$name-$generation.o"
      cmp "$work_dir/$name-1.o" "$work_dir/$name-$generation.o"
    fi
  done
  test "$(nm -u "$work_dir/core-$generation.o" | wc -l)" -eq 0
  "$cross_cc" -Wall -Wextra -Werror "$project_root/bootstrap/driver.c" \
    "$project_root/bootstrap/host/source.c" "$project_root/bootstrap/host/compiler.c" \
    "$work_dir/core-$generation.o" "$work_dir/host-$generation.o" \
    "$work_dir/source-$generation.o" "$work_dir/driver-$generation.o" \
    "$work_dir/input-$generation.o" "$work_dir/path-$generation.o" \
    "$work_dir/output-$generation.o" \
    -o "$work_dir/compiler-$generation"
}

# Rebuild all seven PSL modules on the target, then compare artifacts from
# successive native subset generations. This is not the complete M8 gate.
for generation in 1 2 3; do
  compile_modules "$generation"
  for name in stack_arguments foreign_calls cfg_optimizer inline integer_stack_ffi data_import; do
    run_target "$work_dir/compiler-$generation" --target="$target" \
      "$project_root/tests/bootstrap_$name.lisp" "$work_dir/target-$name.o"
    cmp "$work_dir/$name-1.o" "$work_dir/target-$name.o"
  done
  if test "$target" = riscv64-linux-gnu; then
    run_target "$work_dir/compiler-$generation" --target="$target" \
      "$project_root/tests/bootstrap_riscv64_abi.lisp" "$work_dir/target-abi.o"
    cmp "$work_dir/riscv64_abi-1.o" "$work_dir/target-abi.o"
  fi
  # The cross-target compiler host must still generate identical x86-64 output.
  "$compiler" "$project_root/tests/bootstrap_stack_arguments.lisp" "$work_dir/x86-reference.o"
  run_target "$work_dir/compiler-$generation" "$project_root/tests/bootstrap_stack_arguments.lisp" \
    "$work_dir/x86-target.o"
  cmp "$work_dir/x86-reference.o" "$work_dir/x86-target.o"
done

echo "PSL native $target output, C interoperability, and subset generations passed"
