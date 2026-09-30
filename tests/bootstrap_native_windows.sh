#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
compiler=${PSL_NATIVE_COMPILER:-$project_root/build/pslcc-native}
target=x86_64-windows-gnu
cross_cc=x86_64-w64-mingw32-gcc
cross_ar=x86_64-w64-mingw32-ar
cross_objdump=x86_64-w64-mingw32-objdump
cross_nm=x86_64-w64-mingw32-nm

run_windows() {
  WINEDEBUG=-all wine "$@"
}

check_fixture() {
  name=$1
  level=$2
  extra=
  if test "$name" = foreign_calls; then
    extra="$project_root/tests/bootstrap_foreign_calls.c"
  fi
  "$compiler" "-O$level" --target="$target" \
    "$project_root/tests/bootstrap_$name.lisp" "$work_dir/$name-$level.o"
  "$compiler" --target="$target" "-O$level" \
    "$project_root/tests/bootstrap_$name.lisp" "$work_dir/$name-$level-repeat.o"
  cmp "$work_dir/$name-$level.o" "$work_dir/$name-$level-repeat.o"
  "$cross_objdump" -f "$work_dir/$name-$level.o" | grep -q 'pe-x86-64'
  "$cross_cc" -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_$name.c" \
    $extra "$work_dir/$name-$level.o" -o "$work_dir/$name-$level.exe"
  run_windows "$work_dir/$name-$level.exe"

  "$project_root/pslcc" "-O$level" --target="$target" -c \
    "$project_root/tests/bootstrap_$name.lisp" -o "$work_dir/reference.o"
  "$cross_cc" -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_$name.c" \
    $extra "$work_dir/reference.o" -o "$work_dir/reference.exe"
  run_windows "$work_dir/reference.exe"
}

check_c_source() {
  level=$1
  "$compiler" "-O$level" --target="$target" \
    "$project_root/examples/ffi/source_import.lisp" \
    "$work_dir/source-import-$level.o"
  "$compiler" --target="$target" "-O$level" \
    "$project_root/examples/ffi/source_import.lisp" \
    "$work_dir/source-import-$level-repeat.o"
  cmp "$work_dir/source-import-$level.o" \
    "$work_dir/source-import-$level-repeat.o"
  "$cross_objdump" -f "$work_dir/source-import-$level.o" | grep -q 'pe-x86-64'
  "$cross_cc" -Wall -Wextra -Werror \
    "$project_root/examples/ffi/harness_source_import.c" \
    "$work_dir/source-import-$level.o" -o "$work_dir/source-import-$level.exe"
  run_windows "$work_dir/source-import-$level.exe"
}

for level in 0 1; do
  for name in answer two_functions local_calls six_arguments usize integer_types \
      mixed_integers bitops pointers stack_arguments foreign_calls void_calls \
      layout_queries optimizer cfg_optimizer effects inline integer_stack_ffi \
      data_import data_export c_string; do
    check_fixture "$name" "$level"
  done
  check_c_source "$level"
done

"$cross_objdump" -r "$work_dir/foreign_calls-1.o" | grep -q 'IMAGE_REL_AMD64_REL32.*foreign_seven'
test "$("$cross_objdump" -r "$work_dir/data_import-1.o" | \
  grep -c 'IMAGE_REL_AMD64_REL32.*c_counter')" -eq 4
"$cross_objdump" -r "$work_dir/data_import-1.o" | \
  grep -q 'IMAGE_REL_AMD64_REL32.*MixedCaseData'
"$cross_objdump" -r "$work_dir/foreign_calls-1.o" | grep -q 'IMAGE_REL_AMD64_ADDR32NB.*.xdata'
if "$cross_nm" -u "$work_dir/foreign_calls-1.o" | grep -q unused_foreign; then
  echo 'native Windows output retained an unused import' >&2
  exit 1
fi
if "$cross_nm" -u "$work_dir/data_import-1.o" | grep -q unused_counter; then
  echo 'native Windows output retained an unused data import' >&2
  exit 1
fi
"$cross_objdump" -h "$work_dir/data_export-1.o" | grep -q '\.data'
"$cross_objdump" -t "$work_dir/data_export-1.o" | grep -q 'psl_counter'
"$cross_objdump" -t "$work_dir/data_export-1.o" | grep -q 'MixedCaseExport'
"$cross_objdump" -t "$work_dir/data_export-1.o" | grep -q 'unreferenced_export'
test "$("$cross_objdump" -t "$work_dir/c_string-1.o" | \
  grep -c 'scl   3.*ffi:c-string')" -eq 2
if "$cross_nm" -g "$work_dir/c_string-1.o" | grep -q 'ffi:c-string'; then
  echo 'native Windows output exposed a C string literal' >&2
  exit 1
fi
if "$cross_nm" -u "$work_dir/cfg_optimizer-1.o" | grep -q cfg_dead; then
  echo 'native Windows output retained an unreachable import' >&2
  exit 1
fi
"$cross_cc" -std=gnu11 -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_coff_unwind.c" \
  "$work_dir/answer-1.o" -o "$work_dir/linked-unwind.exe"
run_windows "$work_dir/linked-unwind.exe"

"$cross_cc" -c "$project_root/tests/bootstrap_foreign_calls.c" -o "$work_dir/provider.o"
"$cross_ar" rcs "$work_dir/libforeign.a" "$work_dir/foreign_calls-1.o" "$work_dir/provider.o"
"$cross_cc" "$project_root/tests/harness_bootstrap_foreign_calls.c" \
  "$work_dir/libforeign.a" -o "$work_dir/static.exe"
run_windows "$work_dir/static.exe"
"$cross_cc" -shared "$project_root/tests/bootstrap_foreign_calls.c" \
  "$work_dir/foreign_calls-1.o" "-Wl,--out-implib,$work_dir/libforeign.dll.a" \
  -o "$work_dir/foreign.dll"
"$cross_cc" "$project_root/tests/harness_bootstrap_foreign_calls.c" \
  "$work_dir/libforeign.dll.a" -o "$work_dir/shared.exe"
run_windows "$work_dir/shared.exe"

compile_modules() {
  generation=$1
  for pair in core:bootstrap/native-core.lisp host:bootstrap/host/driver.lisp \
      source:bootstrap/host/source_unit.lisp driver:bootstrap/host/compiler.lisp \
      input:bootstrap/host/source_io.lisp path:bootstrap/host/source_path_windows.lisp \
      output:bootstrap/host/output.lisp diagnostics:bootstrap/host/diagnostics.lisp; do
    name=${pair%%:*}
    source=${pair#*:}
    if test "$generation" -eq 1; then
      "$compiler" --target="$target" "$project_root/$source" "$work_dir/$name-$generation.o"
    else
      run_windows "$work_dir/compiler-$((generation - 1)).exe" --target="$target" \
        "$project_root/$source" "$work_dir/$name-$generation.o"
      cmp "$work_dir/$name-1.o" "$work_dir/$name-$generation.o"
    fi
  done
  test "$("$cross_nm" -u "$work_dir/core-$generation.o" | wc -l)" -eq 0
  "$cross_cc" -Wall -Wextra -Werror "$project_root/bootstrap/driver.c" \
    "$project_root/bootstrap/host/platform_stdio.c" \
    "$project_root/bootstrap/host/platform_toolchain.c" \
    "$work_dir/core-$generation.o" "$work_dir/host-$generation.o" \
    "$work_dir/source-$generation.o" "$work_dir/driver-$generation.o" \
    "$work_dir/input-$generation.o" "$work_dir/path-$generation.o" \
    "$work_dir/output-$generation.o" "$work_dir/diagnostics-$generation.o" \
    -o "$work_dir/compiler-$generation.exe"
}

for generation in 1 2 3; do
  compile_modules "$generation"
  for name in stack_arguments foreign_calls cfg_optimizer inline integer_stack_ffi \
      data_import data_export c_string; do
    run_windows "$work_dir/compiler-$generation.exe" --target="$target" \
      "$project_root/tests/bootstrap_$name.lisp" "$work_dir/target-$name.o"
    cmp "$work_dir/$name-1.o" "$work_dir/target-$name.o"
  done
  "$compiler" "$project_root/tests/bootstrap_stack_arguments.lisp" "$work_dir/x86-reference.o"
  run_windows "$work_dir/compiler-$generation.exe" \
    "$project_root/tests/bootstrap_stack_arguments.lisp" "$work_dir/x86-target.o"
  cmp "$work_dir/x86-reference.o" "$work_dir/x86-target.o"
done

# Exercise the public COFF writer from Linux and Windows compiler hosts.
"$project_root/pslcc" -c "$project_root/bootstrap/native-core.lisp" \
  -o "$work_dir/core-linux-api.o"
cc -std=gnu11 -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_coff.c" "$work_dir/core-linux-api.o" \
  -o "$work_dir/coff-linux-api"
"$work_dir/coff-linux-api" "$work_dir/api-linux.o" "$work_dir/overflow-linux.o"
"$cross_cc" -std=gnu11 -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_coff.c" "$work_dir/core-1.o" \
  -o "$work_dir/coff-windows-api.exe"
run_windows "$work_dir/coff-windows-api.exe" "$work_dir/api-windows.o" "$work_dir/overflow-windows.o"
cmp "$work_dir/api-linux.o" "$work_dir/api-windows.o"
cmp "$work_dir/overflow-linux.o" "$work_dir/overflow-windows.o"
"$cross_cc" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_coff_link.c" "$work_dir/api-linux.o" \
  -o "$work_dir/api-linked.exe"
run_windows "$work_dir/api-linked.exe"
"$cross_cc" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_coff_link.c" "$work_dir/overflow-linux.o" \
  -o "$work_dir/overflow-linked.exe"
run_windows "$work_dir/overflow-linked.exe"

echo 'PSL native Windows COFF output, C interoperability, and subset generations passed'
