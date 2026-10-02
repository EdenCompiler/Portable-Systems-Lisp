#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
host_target=${1:-x86_64-linux-gnu}
host_suffix=

case $host_target in
  x86_64-linux-gnu)
    host_compiler=cc
    path_source=bootstrap/host/source_path_posix.lisp
    path_expect=
    data_format=elf
    data_machine=62
    data_flags=0 ;;
  x86_64-windows-gnu)
    host_compiler=x86_64-w64-mingw32-gcc
    host_suffix=.exe
    path_source=bootstrap/host/source_path_windows.lisp
    path_expect=-DEXPECT_WINDOWS_PATHS=1
    data_format=coff
    data_machine=0
    data_flags=0 ;;
  aarch64-linux-gnu)
    host_compiler=aarch64-linux-gnu-gcc
    path_source=bootstrap/host/source_path_posix.lisp
    path_expect=
    data_format=elf
    data_machine=183
    data_flags=0 ;;
  riscv64-linux-gnu)
    host_compiler=riscv64-linux-gnu-gcc
    path_source=bootstrap/host/source_path_posix.lisp
    path_expect=
    data_format=elf
    data_machine=243
    data_flags=4 ;;
  *) echo "unsupported bootstrap host: $host_target" >&2; exit 2 ;;
esac

module_source() {
  case $1 in
    atoms|reader) printf '%s/bootstrap/frontend/%s.lisp' "$project_root" "$1" ;;
    *) printf '%s/bootstrap/%s.lisp' "$project_root" "$1" ;;
  esac
}

run_host() {
  case $host_target in
    x86_64-linux-gnu) "$@" ;;
    x86_64-windows-gnu) WINEDEBUG=-all wine "$@" ;;
    aarch64-linux-gnu)
      qemu-aarch64 -L "${AARCH64_SYSROOT:-/usr/aarch64-linux-gnu}" "$@" ;;
    riscv64-linux-gnu)
      qemu-riscv64 -L "${RISCV64_SYSROOT:-/usr/riscv64-linux-gnu}" "$@" ;;
  esac
}

if test -n "${PSL_NATIVE_CORE_OBJECT:-}"; then
  cp "$PSL_NATIVE_CORE_OBJECT" "$work_dir/native-core.o"
else
  "$project_root/pslcc" --target="$host_target" -c \
    "$project_root/bootstrap/native-core.lisp" \
    -o "$work_dir/native-core.o"
fi
if test -n "${PSL_NATIVE_HOST_OBJECT:-}"; then
  cp "$PSL_NATIVE_HOST_OBJECT" "$work_dir/native-host.o"
else
  "$project_root/pslcc" --target="$host_target" -c \
    "$project_root/bootstrap/host/driver.lisp" -o "$work_dir/native-host.o"
fi
if test -n "${PSL_NATIVE_SOURCE_OBJECT:-}"; then
  cp "$PSL_NATIVE_SOURCE_OBJECT" "$work_dir/native-source.o"
else
  "$project_root/pslcc" --target="$host_target" -c \
    "$project_root/bootstrap/host/source_unit.lisp" -o "$work_dir/native-source.o"
fi
if test -n "${PSL_NATIVE_INPUT_OBJECT:-}"; then
  cp "$PSL_NATIVE_INPUT_OBJECT" "$work_dir/native-input.o"
else
  "$project_root/pslcc" --target="$host_target" -c \
    "$project_root/bootstrap/host/source_io.lisp" -o "$work_dir/native-input.o"
fi
if test -n "${PSL_NATIVE_PATH_OBJECT:-}"; then
  cp "$PSL_NATIVE_PATH_OBJECT" "$work_dir/native-path.o"
else
  "$project_root/pslcc" --target="$host_target" -c \
    "$project_root/$path_source" -o "$work_dir/native-path.o"
fi
if test -n "${PSL_NATIVE_DRIVER_OBJECT:-}"; then
  cp "$PSL_NATIVE_DRIVER_OBJECT" "$work_dir/native-driver.o"
else
  "$project_root/pslcc" --target="$host_target" -c \
    "$project_root/bootstrap/host/compiler.lisp" -o "$work_dir/native-driver.o"
fi
if test -n "${PSL_NATIVE_OUTPUT_OBJECT:-}"; then
  cp "$PSL_NATIVE_OUTPUT_OBJECT" "$work_dir/native-output.o"
else
  "$project_root/pslcc" --target="$host_target" -c \
    "$project_root/bootstrap/host/output.lisp" -o "$work_dir/native-output.o"
fi
if test -n "${PSL_NATIVE_DIAGNOSTICS_OBJECT:-}"; then
  cp "$PSL_NATIVE_DIAGNOSTICS_OBJECT" "$work_dir/native-diagnostics.o"
else
  "$project_root/pslcc" --target="$host_target" -c \
    "$project_root/bootstrap/host/diagnostics.lisp" \
    -o "$work_dir/native-diagnostics.o"
fi
source_allocator_flags=
if test "$host_target" = x86_64-linux-gnu; then
  source_allocator_flags='-DPSL_TEST_ALLOCATOR_FAULTS -Wl,--wrap=malloc -Wl,--wrap=calloc -Wl,--wrap=realloc -Wl,--wrap=free'
fi
mkdir "$work_dir/source-input-fixtures"
"$host_compiler" -std=c11 -Wall -Wextra -Werror $source_allocator_flags \
  "$project_root/tests/harness_bootstrap_source_io.c" "$work_dir/native-input.o" \
  -o "$work_dir/source-input-check$host_suffix"
run_host "$work_dir/source-input-check$host_suffix" "$work_dir/source-input-fixtures"
"$host_compiler" -std=c11 -Wall -Wextra -Werror $path_expect \
  "$project_root/tests/harness_bootstrap_source_path.c" "$work_dir/native-path.o" \
  -o "$work_dir/source-path-check$host_suffix"
run_host "$work_dir/source-path-check$host_suffix" \
  "$project_root/bootstrap/native-core.lisp" \
  "$project_root/bootstrap/./native-core.lisp" "$work_dir/missing-path"
"$host_compiler" -Wall -Wextra -Werror $source_allocator_flags \
  "$project_root/tests/harness_bootstrap_source_unit.c" \
  "$work_dir/native-core.o" "$work_dir/native-source.o" -o "$work_dir/source-unit-check$host_suffix"
run_host "$work_dir/source-unit-check$host_suffix"
allocator_flags=
if test "$host_target" = x86_64-linux-gnu; then
  allocator_flags='-DPSL_TEST_ALLOCATOR_FAULTS -Wl,--wrap=calloc -Wl,--wrap=free'
fi
"$host_compiler" -Wall -Wextra -Werror $allocator_flags \
  "$project_root/tests/harness_bootstrap_driver.c" \
  "$work_dir/native-core.o" "$work_dir/native-host.o" -o "$work_dir/driver-check$host_suffix"
run_host "$work_dir/driver-check$host_suffix"
"$host_compiler" -Wall -Wextra -Werror $allocator_flags \
  "$project_root/tests/harness_bootstrap_compiler.c" "$work_dir/native-driver.o" \
  -o "$work_dir/compiler-driver-check$host_suffix"
run_host "$work_dir/compiler-driver-check$host_suffix"
"$host_compiler" -Wall -Wextra -Werror "$project_root/bootstrap/driver.c" \
  "$project_root/bootstrap/host/platform_stdio.c" \
  "$project_root/bootstrap/host/platform_toolchain.c" \
  "$work_dir/native-core.o" "$work_dir/native-host.o" "$work_dir/native-source.o" \
  "$work_dir/native-input.o" "$work_dir/native-path.o" \
  "$work_dir/native-driver.o" "$work_dir/native-output.o" \
  "$work_dir/native-diagnostics.o" -o "$work_dir/pslcc-native-slice$host_suffix"

# Compare object data emitted by a Stage 0 writer and a writer built by the
# native compiler. Their own code bytes may differ while behavior must agree.
"$project_root/pslcc" -O1 --target="$host_target" -c \
  "$project_root/bootstrap/object/static_data.lisp" \
  -o "$work_dir/static-data-stage0.o"
run_host "$work_dir/pslcc-native-slice$host_suffix" -O1 --target="$host_target" \
  "$project_root/bootstrap/object/static_data.lisp" \
  "$work_dir/static-data-native.o"
for writer in stage0 native; do
  "$host_compiler" -std=c11 -Wall -Wextra -Werror \
    "$project_root/tests/harness_bootstrap_static_data_writer.c" \
    "$work_dir/static-data-$writer.o" \
    -o "$work_dir/static-data-$writer$host_suffix"
  run_host "$work_dir/static-data-$writer$host_suffix" "$data_format" \
    "$work_dir/static-data-output-$writer.o" "$data_machine" "$data_flags"
done
cmp "$work_dir/static-data-output-stage0.o" \
    "$work_dir/static-data-output-native.o"
"$host_compiler" -std=c11 -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_static_data.c" \
  "$work_dir/static-data-output-native.o" \
  -o "$work_dir/static-data-check$host_suffix"
run_host "$work_dir/static-data-check$host_suffix"

check_cli_failure() {
  expected=$1
  shift
  if run_host "$work_dir/pslcc-native-slice$host_suffix" "$@" \
      >"$work_dir/cli.out" 2>"$work_dir/cli.err"; then
    echo 'native driver accepted an expected failure' >&2
    exit 1
  else
    status=$?
    test "$status" -eq "$expected"
  fi
}
check_cli_failure 2
check_cli_failure 2 unused
check_cli_failure 2 one two three
grep -q 'usage: pslcc-native-slice' "$work_dir/cli.err"
check_cli_failure 2 "$work_dir/missing.lisp" "$work_dir/cli-rejected.o"
grep -q 'cannot read source' "$work_dir/cli.err"
test ! -e "$work_dir/cli-rejected.o"
check_cli_failure 1 "$project_root/tests/bootstrap_wrong_arity.lisp" "$work_dir/cli-rejected.o"
grep -q 'unsupported or malformed source' "$work_dir/cli.err"
test ! -e "$work_dir/cli-rejected.o"
mkdir "$work_dir/output-directory"
check_cli_failure 2 "$project_root/tests/bootstrap_answer.lisp" "$work_dir/output-directory"
grep -q 'cannot write object' "$work_dir/cli.err"
if test "$host_target" = x86_64-linux-gnu; then
  for level in 0 1; do
    run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
      "$project_root/examples/ffi/source_import.lisp" \
      "$work_dir/source-import-$level.o"
    run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
      "$project_root/examples/ffi/source_import.lisp" \
      "$work_dir/source-import-$level-repeat.o"
    cmp "$work_dir/source-import-$level.o" \
      "$work_dir/source-import-$level-repeat.o"
    cc -Wall -Wextra -Werror \
      "$project_root/examples/ffi/harness_source_import.c" \
      "$work_dir/source-import-$level.o" -o "$work_dir/source-import-$level"
    "$work_dir/source-import-$level"
  done
  run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/include/entry.lisp" "$work_dir/include-c-source.o"
  cc -Wall -Wextra -Werror "$project_root/tests/include/harness.c" \
    "$work_dir/include-c-source.o" -o "$work_dir/include-c-source"
  "$work_dir/include-c-source"
  check_cli_failure 2 "$project_root/tests/include/missing_c_source.lisp" \
    "$work_dir/missing-c-source.o"
  grep -q 'cannot read source' "$work_dir/cli.err"
  test ! -e "$work_dir/missing-c-source.o"
  check_cli_failure 2 "$project_root/tests/include/duplicate_c_source.lisp" \
    "$work_dir/duplicate-c-source.o"
  grep -q 'duplicate C source' "$work_dir/cli.err"
  test ! -e "$work_dir/duplicate-c-source.o"
  check_cli_failure 2 "$project_root/tests/include/invalid_c_source.lisp" \
    "$work_dir/invalid-c-source.o"
  grep -q 'cannot write object' "$work_dir/cli.err"
  test ! -e "$work_dir/invalid-c-source.o"
fi
for level in 0 1; do
  run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
    "$project_root/tests/bootstrap_optimizer.lisp" "$work_dir/optimizer-$level.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_optimizer.c" \
    "$work_dir/optimizer-$level.o" -o "$work_dir/optimizer-$level"
  "$work_dir/optimizer-$level"
  run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
    "$project_root/tests/bootstrap_optimizer.lisp" "$work_dir/optimizer-$level-repeat.o"
  cmp "$work_dir/optimizer-$level.o" "$work_dir/optimizer-$level-repeat.o"
  "$project_root/pslcc" "-O$level" -c "$project_root/tests/bootstrap_optimizer.lisp" \
    -o "$work_dir/optimizer-stage0-$level.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_optimizer.c" \
    "$work_dir/optimizer-stage0-$level.o" -o "$work_dir/optimizer-stage0-$level"
  "$work_dir/optimizer-stage0-$level"
done
test "$(wc -c < "$work_dir/optimizer-1.o")" -lt "$(wc -c < "$work_dir/optimizer-0.o")"
# This expression depends on its argument, so folding cannot explain removal.
dead_size0=$(nm -S --radix=d "$work_dir/optimizer-0.o" | awk '$4 == "dead_arithmetic" {print $2}')
dead_size1=$(nm -S --radix=d "$work_dir/optimizer-1.o" | awk '$4 == "dead_arithmetic" {print $2}')
test "$dead_size1" -lt "$dead_size0"
for level in 0 1; do
  run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
    "$project_root/tests/bootstrap_cfg_optimizer.lisp" "$work_dir/cfg-$level.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_cfg_optimizer.c" \
    "$work_dir/cfg-$level.o" -o "$work_dir/cfg-$level"
  "$work_dir/cfg-$level"
  run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
    "$project_root/tests/bootstrap_cfg_optimizer.lisp" "$work_dir/cfg-$level-repeat.o"
  cmp "$work_dir/cfg-$level.o" "$work_dir/cfg-$level-repeat.o"
  "$project_root/pslcc" "-O$level" -c "$project_root/tests/bootstrap_cfg_optimizer.lisp" \
    -o "$work_dir/cfg-stage0-$level.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_cfg_optimizer.c" \
    "$work_dir/cfg-stage0-$level.o" -o "$work_dir/cfg-stage0-$level"
  "$work_dir/cfg-stage0-$level"
done
nm -u "$work_dir/cfg-0.o" | grep -q 'cfg_dead'
if nm -u "$work_dir/cfg-1.o" | grep -q 'cfg_dead'; then
  echo 'native CFG optimization retained an unreachable import' >&2
  exit 1
fi
test "$(wc -c < "$work_dir/cfg-1.o")" -lt "$(wc -c < "$work_dir/cfg-0.o")"
for level in 0 1; do
  run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
    "$project_root/tests/bootstrap_inline.lisp" "$work_dir/inline-$level.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_inline.c" \
    "$work_dir/inline-$level.o" -o "$work_dir/inline-$level"
  "$work_dir/inline-$level"
  run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
    "$project_root/tests/bootstrap_inline.lisp" "$work_dir/inline-$level-repeat.o"
  cmp "$work_dir/inline-$level.o" "$work_dir/inline-$level-repeat.o"
  "$project_root/pslcc" "-O$level" -c "$project_root/tests/bootstrap_inline.lisp" \
    -o "$work_dir/inline-stage0-$level.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_inline.c" \
    "$work_dir/inline-stage0-$level.o" -o "$work_dir/inline-stage0-$level"
  "$work_dir/inline-stage0-$level"
done
objdump -d "$work_dir/inline-0.o" | grep -q 'call.*<inline_pair>'
if objdump -d "$work_dir/inline-1.o" | grep -q 'call.*<inline_pair>'; then
  echo 'native inliner retained an eligible direct call' >&2
  exit 1
fi
objdump -d "$work_dir/inline-1.o" | grep -q 'call.*<inline_load>'
"$host_compiler" -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_inline_api.c" \
  "$work_dir/native-core.o" "$work_dir/native-host.o" -o "$work_dir/inline-api$host_suffix"
run_host "$work_dir/inline-api$host_suffix"
for level in 0 1; do
  run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
    "$project_root/tests/bootstrap_effects.lisp" "$work_dir/effects-$level.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_effects.c" \
    "$work_dir/effects-$level.o" -o "$work_dir/effects-$level"
  "$work_dir/effects-$level"
  run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
    "$project_root/tests/bootstrap_effects.lisp" "$work_dir/effects-$level-repeat.o"
  cmp "$work_dir/effects-$level.o" "$work_dir/effects-$level-repeat.o"
  "$project_root/pslcc" "-O$level" -c "$project_root/tests/bootstrap_effects.lisp" \
    -o "$work_dir/effects-stage0-$level.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_effects.c" \
    "$work_dir/effects-stage0-$level.o" -o "$work_dir/effects-stage0-$level"
  "$work_dir/effects-stage0-$level"
  for source in "$project_root"/tests/bootstrap_effect_errors/*.lisp; do
    check_cli_failure 1 "-O$level" "$source" "$work_dir/effect-rejected.o"
    test ! -e "$work_dir/effect-rejected.o"
    case ${source##*/} in
      annotation.lisp|empty.lisp) ;;
      *) grep -q 'WITHOUT-ALLOCATION cannot certify call to' "$work_dir/cli.err" ;;
    esac
    if "$project_root/pslcc" "-O$level" -c "$source" -o "$work_dir/effect-rejected.o" \
        >"$work_dir/effect-stage0.out" 2>"$work_dir/effect-stage0.err"; then
      echo 'Stage 0 accepted an invalid allocation region' >&2
      exit 1
    fi
    test ! -e "$work_dir/effect-rejected.o"
  done
done
for level in 0 1; do
  for fixture in bootstrap_stack_arguments bootstrap_pointers bootstrap_mixed_integers \
      bootstrap_foreign_calls bootstrap_void_calls; do
    run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
      "$project_root/tests/$fixture.lisp" "$work_dir/$fixture-native-level-$level.o"
    case $fixture in
      bootstrap_stack_arguments) harness=harness_bootstrap_stack_arguments; extra= ;;
      bootstrap_pointers) harness=harness_bootstrap_pointers; extra= ;;
      bootstrap_mixed_integers) harness=harness_bootstrap_mixed_integers; extra= ;;
      bootstrap_foreign_calls) harness=harness_bootstrap_foreign_calls; extra="$project_root/tests/bootstrap_foreign_calls.c" ;;
      bootstrap_void_calls) harness=harness_bootstrap_void_calls; extra= ;;
    esac
    cc -Wall -Wextra -Werror "$project_root/tests/$harness.c" $extra \
      "$work_dir/$fixture-native-level-$level.o" -o "$work_dir/$fixture-native-level-$level"
    "$work_dir/$fixture-native-level-$level"
  done
done
check_cli_failure 2 -O2 "$project_root/tests/bootstrap_answer.lisp" "$work_dir/cli-rejected.o"
grep -q 'usage: pslcc-native-slice' "$work_dir/cli.err"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/bootstrap/host/driver.lisp" "$work_dir/native-host-native.o"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/bootstrap/host/source_unit.lisp" "$work_dir/native-source-native.o"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/bootstrap/host/source_io.lisp" "$work_dir/native-input-native.o"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/$path_source" "$work_dir/native-path-native.o"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/bootstrap/host/compiler.lisp" "$work_dir/native-driver-native.o"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/bootstrap/host/output.lisp" "$work_dir/native-output-native.o"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/bootstrap/host/diagnostics.lisp" \
  "$work_dir/native-diagnostics-native.o"
if test "$host_target" = x86_64-linux-gnu; then
  cc -Wall -Wextra -Werror $allocator_flags \
    "$project_root/tests/harness_bootstrap_compiler.c" "$work_dir/native-driver-native.o" \
    -o "$work_dir/compiler-native-check"
  "$work_dir/compiler-native-check"
fi
if test "$host_target" = x86_64-linux-gnu; then
  cc -Wall -Wextra -Werror $source_allocator_flags \
    "$project_root/tests/harness_bootstrap_source_unit.c" \
    "$work_dir/native-core.o" "$work_dir/native-source-native.o" -o "$work_dir/source-native-check"
  "$work_dir/source-native-check"
fi
test "$(nm -u "$work_dir/native-host-native.o" | wc -l)" -eq 2
nm -u "$work_dir/native-host-native.o" | grep -q ' U calloc$'
nm -u "$work_dir/native-host-native.o" | grep -q ' U free$'
if test "$host_target" = x86_64-linux-gnu; then
  cc -Wall -Wextra -Werror $allocator_flags \
    "$project_root/tests/harness_bootstrap_driver.c" \
    "$work_dir/native-core.o" "$work_dir/native-host-native.o" -o "$work_dir/driver-native-check"
  "$work_dir/driver-native-check"
fi
"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_unit.c" \
  "$work_dir/native-core.o" -o "$work_dir/unit-api$host_suffix"
run_host "$work_dir/unit-api$host_suffix" "$work_dir/unit-api.o"
readelf -r "$work_dir/unit-api.o" | grep -q 'R_X86_64_PLT32.*unit_c - 4'
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_unit_output.c" \
  "$work_dir/unit-api.o" -o "$work_dir/unit-api-output"
"$work_dir/unit-api-output"
"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_hir.c" \
  "$work_dir/native-core.o" -o "$work_dir/hir-verifier$host_suffix"
run_host "$work_dir/hir-verifier$host_suffix"
"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_memory_hir.c" \
  "$work_dir/native-core.o" -o "$work_dir/memory-hir-verifier$host_suffix"
run_host "$work_dir/memory-hir-verifier$host_suffix"
"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_ir.c" \
  "$work_dir/native-core.o" -o "$work_dir/ir-verifier$host_suffix"
run_host "$work_dir/ir-verifier$host_suffix"
"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_layout.c" \
  "$work_dir/native-core.o" -o "$work_dir/layout-check$host_suffix"
run_host "$work_dir/layout-check$host_suffix"
"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_signatures.c" \
  "$project_root/tests/provider_bootstrap_source_diagnostics.c" \
  "$work_dir/native-core.o" "$work_dir/native-source.o" "$work_dir/native-input.o" \
  "$work_dir/native-path.o" \
  -o "$work_dir/signature-check$host_suffix"
run_host "$work_dir/signature-check$host_suffix" \
  "$project_root/bootstrap/binary.lisp" \
  "$project_root/bootstrap/arena.lisp" \
  "$project_root/bootstrap/frontend/atoms.lisp" \
  "$project_root/bootstrap/frontend/reader.lisp"

"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_source.c" \
  "$work_dir/native-core.o" -o "$work_dir/source-check$host_suffix"
run_host "$work_dir/source-check$host_suffix"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/include/native/main.lisp" "$work_dir/included.o"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/include/native/flat.lisp" "$work_dir/included-flat.o"
cmp "$work_dir/included.o" "$work_dir/included-flat.o"
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_answer.c" \
  "$work_dir/included.o" -o "$work_dir/included"
"$work_dir/included"

if test "$host_target" = x86_64-linux-gnu; then
  ln -s "$project_root/tests/include/native/shared.lisp" "$work_dir/shared-one.lisp"
  ln -s "$project_root/tests/include/native/shared.lisp" "$work_dir/shared-two.lisp"
  cat > "$work_dir/symlink-unit.lisp" <<'EOF'
(include "shared-one.lisp")
(include "shared-two.lisp")
(defun answer ()
  (declare (returns u64) (c-export :c))
  (included_helper 41))
EOF
  "$work_dir/pslcc-native-slice" "$work_dir/symlink-unit.lisp" "$work_dir/symlink-unit.o"
  cmp "$work_dir/included.o" "$work_dir/symlink-unit.o"
fi

for source in cycle-a missing invalid unterminated; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" \
      "$project_root/tests/include/native/$source.lisp" "$work_dir/invalid-include.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted invalid include: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid-include.o"
  case $source in
    cycle-a) grep -q 'circular source include' "$work_dir/stderr" ;;
    missing) grep -q 'cannot read source' "$work_dir/stderr" ;;
    invalid) grep -q 'invalid include form' "$work_dir/stderr" ;;
    unterminated) grep -q 'reader error' "$work_dir/stderr" ;;
  esac
done

for module in parser source; do
  run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/bootstrap/frontend/$module.lisp" "$work_dir/$module-native.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_$module.c" \
    "$work_dir/$module-native.o" -o "$work_dir/$module-native"
  "$work_dir/$module-native" "$project_root"/examples/*/*.lisp
  test "$(nm -u "$work_dir/$module-native.o" | wc -l)" -eq 0
done

"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_relocations.c" \
  "$work_dir/native-core.o" -o "$work_dir/relocation-check$host_suffix"
run_host "$work_dir/relocation-check$host_suffix"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_foreign_calls.lisp" "$work_dir/foreign-calls.o"
readelf -r "$work_dir/foreign-calls.o" > "$work_dir/foreign-relocations"
test "$(grep -c R_X86_64_PLT32 "$work_dir/foreign-relocations")" -eq 7
for symbol in foreign_seven foreign_eight foreign_narrow foreign_pointer strlen \
    foreign_integer_zero foreign_pointer_zero; do
  grep -q " $symbol - 4$" "$work_dir/foreign-relocations"
  nm -u "$work_dir/foreign-calls.o" | grep -q " U $symbol$"
done
if nm "$work_dir/foreign-calls.o" | grep -q 'unused_foreign'; then
  echo 'native object retained an unused C import' >&2
  exit 1
fi
cc -Wall -Wextra -Werror -fPIC -c "$project_root/tests/bootstrap_foreign_calls.c" \
  -o "$work_dir/foreign-c.o"
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_foreign_calls.c" \
  "$work_dir/foreign-calls.o" "$work_dir/foreign-c.o" -o "$work_dir/foreign-calls"
"$work_dir/foreign-calls"
"$project_root/pslcc" -c "$project_root/tests/bootstrap_foreign_calls.lisp" \
  -o "$work_dir/foreign-stage0.o"
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_foreign_calls.c" \
  "$work_dir/foreign-stage0.o" "$work_dir/foreign-c.o" -o "$work_dir/foreign-stage0"
"$work_dir/foreign-stage0"
cc -shared "$work_dir/foreign-calls.o" "$work_dir/foreign-c.o" -o "$work_dir/libforeign.so"
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_foreign_calls.c" \
  -L"$work_dir" -lforeign -Wl,-rpath,"$work_dir" -o "$work_dir/foreign-shared"
"$work_dir/foreign-shared"
ar rcs "$work_dir/libforeign.a" "$work_dir/foreign-calls.o" "$work_dir/foreign-c.o"
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_foreign_calls.c" \
  "$work_dir/libforeign.a" -o "$work_dir/foreign-static"
"$work_dir/foreign-static"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_foreign_calls.lisp" "$work_dir/foreign-repeat.o"
cmp "$work_dir/foreign-calls.o" "$work_dir/foreign-repeat.o"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_import_case.lisp" "$work_dir/import-case.o"
nm -u "$work_dir/import-case.o" | grep -q ' U MixedCaseAdd$'
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_import_case.c" \
  "$work_dir/import-case.o" -o "$work_dir/import-case"
"$work_dir/import-case"
"$project_root/pslcc" -c "$project_root/tests/bootstrap_import_case.lisp" \
  -o "$work_dir/import-case-stage0.o"
nm -u "$work_dir/import-case-stage0.o" | grep -q ' U MixedCaseAdd$'
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_import_case.c" \
  "$work_dir/import-case-stage0.o" -o "$work_dir/import-case-stage0"
"$work_dir/import-case-stage0"
for level in 0 1; do
  run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
    "$project_root/tests/bootstrap_data_import.lisp" "$work_dir/data-import-$level.o"
  run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
    "$project_root/tests/bootstrap_data_import.lisp" "$work_dir/data-import-$level-repeat.o"
  cmp "$work_dir/data-import-$level.o" "$work_dir/data-import-$level-repeat.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_data_import.c" \
    "$work_dir/data-import-$level.o" -o "$work_dir/data-import-$level"
  "$work_dir/data-import-$level"
  "$project_root/pslcc" "-O$level" -c \
    "$project_root/tests/bootstrap_data_import.lisp" \
    -o "$work_dir/data-import-stage0-$level.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_data_import.c" \
    "$work_dir/data-import-stage0-$level.o" -o "$work_dir/data-import-stage0-$level"
  "$work_dir/data-import-stage0-$level"
done
test "$(readelf -r "$work_dir/data-import-1.o" | grep -c R_X86_64_GOTPCREL)" -eq 5
nm -u "$work_dir/data-import-1.o" | grep -q ' U c_counter$'
nm -u "$work_dir/data-import-1.o" | grep -q ' U MixedCaseData$'
if nm -u "$work_dir/data-import-1.o" | grep -q unused_counter; then
  echo 'native object retained an unused C data import' >&2
  exit 1
fi
for level in 0 1; do
  run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
    "$project_root/tests/bootstrap_data_export.lisp" "$work_dir/data-export-$level.o"
  run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
    "$project_root/tests/bootstrap_data_export.lisp" \
    "$work_dir/data-export-$level-repeat.o"
  cmp "$work_dir/data-export-$level.o" "$work_dir/data-export-$level-repeat.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_data_export.c" \
    "$work_dir/data-export-$level.o" -o "$work_dir/data-export-$level"
  "$work_dir/data-export-$level"
  "$project_root/pslcc" "-O$level" -c \
    "$project_root/tests/bootstrap_data_export.lisp" \
    -o "$work_dir/data-export-stage0-$level.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_data_export.c" \
    "$work_dir/data-export-stage0-$level.o" -o "$work_dir/data-export-stage0-$level"
  "$work_dir/data-export-stage0-$level"
done
readelf -SW "$work_dir/data-export-1.o" | grep -q '\.data.*PROGBITS'
readelf -sW "$work_dir/data-export-1.o" | grep -q 'OBJECT.*GLOBAL.*psl_counter'
readelf -sW "$work_dir/data-export-1.o" | grep -q 'OBJECT.*GLOBAL.*MixedCaseExport'
readelf -sW "$work_dir/data-export-1.o" | grep -q 'OBJECT.*GLOBAL.*unreferenced_export'
for level in 0 1; do
  run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
    "$project_root/tests/bootstrap_c_string.lisp" "$work_dir/c-string-$level.o"
  run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
    "$project_root/tests/bootstrap_c_string.lisp" "$work_dir/c-string-$level-repeat.o"
  cmp "$work_dir/c-string-$level.o" "$work_dir/c-string-$level-repeat.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_c_string.c" \
    "$work_dir/c-string-$level.o" -o "$work_dir/c-string-$level"
  "$work_dir/c-string-$level"
  "$project_root/pslcc" "-O$level" -c \
    "$project_root/tests/bootstrap_c_string.lisp" \
    -o "$work_dir/c-string-stage0-$level.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_c_string.c" \
    "$work_dir/c-string-stage0-$level.o" -o "$work_dir/c-string-stage0-$level"
  "$work_dir/c-string-stage0-$level"
done
test "$(readelf -sW "$work_dir/c-string-1.o" | grep -c 'OBJECT.*LOCAL')" -eq 2
if nm -g "$work_dir/c-string-1.o" | grep -q 'ffi:c-string'; then
  echo 'native object exposed a C string literal as a global symbol' >&2
  exit 1
fi
for source in "$project_root"/tests/bootstrap_c_string_errors/*.lisp; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" "$source" \
      "$work_dir/invalid-c-string.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted invalid C string source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid-c-string.o"
  if "$project_root/pslcc" -c "$source" -o "$work_dir/invalid-c-string-stage0.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "Stage 0 accepted invalid C string source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid-c-string-stage0.o"
done
for source in "$project_root"/tests/bootstrap_data_errors/*.lisp; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" "$source" \
      "$work_dir/invalid-data.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted invalid data declaration source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid-data.o"
  if "$project_root/pslcc" -c "$source" -o "$work_dir/invalid-data-stage0.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "Stage 0 accepted invalid data declaration source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid-data-stage0.o"
done
for source in "$project_root"/tests/bootstrap_foreign_errors/*.lisp; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" "$source" "$work_dir/invalid-foreign.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted invalid foreign source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid-foreign.o"
done

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_void_calls.lisp" "$work_dir/void-calls.o"
for symbol in malloc free void_store_c void_seven_c; do
  readelf -r "$work_dir/void-calls.o" | grep -q "R_X86_64_PLT32.*$symbol - 4"
done
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_void_calls.c" \
  "$work_dir/void-calls.o" -o "$work_dir/void-calls"
"$work_dir/void-calls"
"$project_root/pslcc" -c "$project_root/tests/bootstrap_void_calls.lisp" \
  -o "$work_dir/void-stage0.o"
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_void_calls.c" \
  "$work_dir/void-stage0.o" -o "$work_dir/void-stage0"
"$work_dir/void-stage0"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_void_calls.lisp" "$work_dir/void-repeat.o"
cmp "$work_dir/void-calls.o" "$work_dir/void-repeat.o"
for source in "$project_root"/tests/bootstrap_void_errors/*.lisp; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" "$source" "$work_dir/invalid-void.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted invalid void source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid-void.o"
done

for source in bootstrap_answer bootstrap_answer_hex \
    bootstrap_answer_arithmetic bootstrap_answer_overflow \
    bootstrap_conditionals bootstrap_recursion bootstrap_layouts \
    bootstrap_bitops bootstrap_lexical \
    bootstrap_declaration_order bootstrap_lisp_names bootstrap_symbols; do
  run_host "$work_dir/pslcc-native-slice$host_suffix" "$project_root/tests/$source.lisp" \
    "$work_dir/$source.o"
  readelf -h "$work_dir/$source.o" | grep -q 'REL (Relocatable file)'
  cc -Wall -Wextra -Werror \
    "$project_root/tests/harness_bootstrap_answer.c" \
    "$work_dir/$source.o" -o "$work_dir/$source"
  "$work_dir/$source"
  run_host "$work_dir/pslcc-native-slice$host_suffix" "$project_root/tests/$source.lisp" \
    "$work_dir/$source-repeat.o"
  cmp "$work_dir/$source.o" "$work_dir/$source-repeat.o"
done

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_layout_queries.lisp" "$work_dir/layout-queries.o"
test -z "$(nm -u "$work_dir/layout-queries.o")"
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_layout_queries.c" \
  "$work_dir/layout-queries.o" -o "$work_dir/layout-queries"
"$work_dir/layout-queries"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_layout_queries.lisp" "$work_dir/layout-queries-repeat.o"
cmp "$work_dir/layout-queries.o" "$work_dir/layout-queries-repeat.o"
for source in "$project_root"/tests/bootstrap_query_errors/*.lisp; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" "$source" "$work_dir/invalid-query.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted invalid layout/address source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid-query.o"
done

nm --defined-only "$work_dir/bootstrap_lisp_names.o" | \
  grep -q ' t helper-one$'
if nm -g --defined-only "$work_dir/bootstrap_lisp_names.o" | \
    grep -q ' helper-one$'; then
  echo 'native slice exported an internal hyphenated function' >&2
  exit 1
fi

cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_bitops.c" \
  "$work_dir/bootstrap_bitops.o" -o "$work_dir/bitops"
"$work_dir/bitops"

for source in bootstrap_lexical_duplicate bootstrap_lexical_scope; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" \
      "$project_root/tests/$source.lisp" "$work_dir/$source.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted invalid lexical source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/$source.o"
done

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_two_functions.lisp" \
  "$work_dir/two-functions.o"
nm -g --defined-only "$work_dir/two-functions.o" | grep -q ' answer$'
nm -g --defined-only "$work_dir/two-functions.o" | grep -q ' other_answer$'
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_two_functions.c" \
  "$work_dir/two-functions.o" -o "$work_dir/two-functions"
"$work_dir/two-functions"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_two_functions.lisp" \
  "$work_dir/two-functions-repeat.o"
cmp "$work_dir/two-functions.o" "$work_dir/two-functions-repeat.o"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_local_calls.lisp" \
  "$work_dir/local-calls.o"
test "$(nm -u "$work_dir/local-calls.o" | wc -l)" -eq 0
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_local_calls.c" \
  "$work_dir/local-calls.o" -o "$work_dir/local-calls"
"$work_dir/local-calls"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_parameters.lisp" \
  "$work_dir/parameters.o"
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_parameters.c" \
  "$work_dir/parameters.o" -o "$work_dir/parameters"
"$work_dir/parameters"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_six_arguments.lisp" \
  "$work_dir/six-arguments.o"
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_six_arguments.c" \
  "$work_dir/six-arguments.o" -o "$work_dir/six-arguments"
"$work_dir/six-arguments"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_six_arguments.lisp" \
  "$work_dir/six-arguments-repeat.o"
cmp "$work_dir/six-arguments.o" "$work_dir/six-arguments-repeat.o"

# Cross the six-register SysV boundary with odd/even stack counts, narrow
# signed values, pointers, nested/recursive calls, and ordered side effects.
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_stack_arguments.lisp" "$work_dir/stack-arguments.o"
test "$(nm -u "$work_dir/stack-arguments.o" | wc -l)" -eq 0
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_stack_arguments.c" \
  "$work_dir/stack-arguments.o" -o "$work_dir/stack-arguments"
"$work_dir/stack-arguments"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_stack_arguments.lisp" "$work_dir/stack-arguments-repeat.o"
cmp "$work_dir/stack-arguments.o" "$work_dir/stack-arguments-repeat.o"
"$project_root/pslcc" -c "$project_root/tests/bootstrap_stack_arguments.lisp" \
  -o "$work_dir/stack-arguments-stage0.o"
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_stack_arguments.c" \
  "$work_dir/stack-arguments-stage0.o" -o "$work_dir/stack-arguments-stage0"
"$work_dir/stack-arguments-stage0"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_usize.lisp" \
  "$work_dir/usize.o"
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_usize.c" \
  "$work_dir/usize.o" -o "$work_dir/usize"
"$work_dir/usize"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_usize.lisp" \
  "$work_dir/usize-repeat.o"
cmp "$work_dir/usize.o" "$work_dir/usize-repeat.o"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_integer_types.lisp" \
  "$work_dir/integer-types.o"
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_integer_types.c" \
  "$work_dir/integer-types.o" -o "$work_dir/integer-types"
"$work_dir/integer-types"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_integer_types.lisp" \
  "$work_dir/integer-types-repeat.o"
cmp "$work_dir/integer-types.o" "$work_dir/integer-types-repeat.o"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_mixed_integers.lisp" \
  "$work_dir/mixed-integers.o"
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_mixed_integers.c" \
  "$work_dir/mixed-integers.o" -o "$work_dir/mixed-integers"
"$work_dir/mixed-integers"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_mixed_integers.lisp" \
  "$work_dir/mixed-integers-repeat.o"
cmp "$work_dir/mixed-integers.o" "$work_dir/mixed-integers-repeat.o"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/bootstrap/ir/integer_types.lisp" \
  "$work_dir/integer-module.o"
test "$(nm -u "$work_dir/integer-module.o" | wc -l)" -eq 0
readelf -h "$work_dir/integer-module.o" | grep -q 'REL (Relocatable file)'
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_integer_module.c" \
  "$work_dir/integer-module.o" -o "$work_dir/integer-module"
"$work_dir/integer-module"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/bootstrap/ir/integer_types.lisp" \
  "$work_dir/integer-module-repeat.o"
cmp "$work_dir/integer-module.o" "$work_dir/integer-module-repeat.o"
"$project_root/pslcc" --target=x86_64-linux-gnu -c \
  "$project_root/bootstrap/ir/integer_types.lisp" \
  -o "$work_dir/integer-module-stage0.o"
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_integer_module.c" \
  "$work_dir/integer-module-stage0.o" -o "$work_dir/integer-module-stage0"
"$work_dir/integer-module-stage0"

for source in bootstrap_usize bootstrap_integer_types bootstrap_mixed_integers; do
  "$project_root/pslcc" --target=x86_64-linux-gnu -c \
    "$project_root/tests/$source.lisp" -o "$work_dir/$source-stage0.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_$source.c" \
    "$work_dir/$source-stage0.o" -o "$work_dir/$source-stage0"
  "$work_dir/$source-stage0"
done

# The native executable compiles real pointer-using compiler modules.
for module in binary arena reader atoms; do
  run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$(module_source "$module")" "$work_dir/$module-module.o"
  test "$(nm -u "$work_dir/$module-module.o" | wc -l)" -eq 0
  readelf -h "$work_dir/$module-module.o" | grep -q 'REL (Relocatable file)'
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_$module.c" \
    "$work_dir/$module-module.o" -o "$work_dir/$module-module"
  "$work_dir/$module-module" "$project_root"/examples/*/*.lisp \
    >"$work_dir/$module-native-output"
  "$project_root/pslcc" -c "$(module_source "$module")" \
    -o "$work_dir/$module-module-stage0.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_$module.c" \
    "$work_dir/$module-module-stage0.o" -o "$work_dir/$module-module-stage0"
  "$work_dir/$module-module-stage0" "$project_root"/examples/*/*.lisp \
    >"$work_dir/$module-stage0-output"
  cmp "$work_dir/$module-native-output" "$work_dir/$module-stage0-output"
  run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$(module_source "$module")" "$work_dir/$module-module-repeat.o"
  cmp "$work_dir/$module-module.o" "$work_dir/$module-module-repeat.o"
done

# Keep the qualifier and packed-layout fixtures in the native bootstrap gate.
# These compile and run on the selected host/output target and compare with
# Stage 0, while checking deterministic native output.
PSL_NATIVE_COMPILER=$work_dir/pslcc-native-slice$host_suffix \
PSL_NATIVE_COMPILER_HOST_TARGET=$host_target \
  sh "$project_root/tests/bootstrap_packed.sh" "$host_target"
PSL_NATIVE_COMPILER_HOST_TARGET=$host_target \
  sh "$project_root/tests/bootstrap_pointer_qualifiers.sh" \
    "$work_dir/pslcc-native-slice$host_suffix" "$host_target"
PSL_NATIVE_COMPILER_HOST_TARGET=$host_target \
  sh "$project_root/tests/bootstrap_c_aliases.sh" \
    "$work_dir/pslcc-native-slice$host_suffix" "$host_target"
PSL_NATIVE_COMPILER_HOST_TARGET=$host_target \
  sh "$project_root/tests/bootstrap_data_only.sh" \
    "$work_dir/pslcc-native-slice$host_suffix" "$host_target"

for check in float_abi float_memory; do
  PSL_NATIVE_COMPILER_HOST_TARGET=$host_target \
    sh "$project_root/tests/bootstrap_$check.sh" \
      "$work_dir/pslcc-native-slice$host_suffix" "$host_target"
done
# Preserve floating objects in the generation snapshot, including both modes.
for name in float_reader float_memory float_abi; do
  for level in 0 1; do
    run_host "$work_dir/pslcc-native-slice$host_suffix" "-O$level" \
      "$project_root/tests/bootstrap_$name.lisp" "$work_dir/$name-$level.o"
  done
done

if test "$host_target" = x86_64-linux-gnu; then
  PATH=/nonexistent "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/bootstrap/binary.lisp" "$work_dir/binary-no-tools.o"
  cmp "$work_dir/binary-module.o" "$work_dir/binary-no-tools.o"
  PATH=/nonexistent "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_stack_arguments.lisp" "$work_dir/stack-no-tools.o"
  cmp "$work_dir/stack-arguments.o" "$work_dir/stack-no-tools.o"
fi

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_pointers.lisp" "$work_dir/pointers.o"
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_pointers.c" \
  "$work_dir/pointers.o" -o "$work_dir/pointers"
"$work_dir/pointers"
"$project_root/pslcc" -c "$project_root/tests/bootstrap_pointers.lisp" \
  -o "$work_dir/pointers-stage0.o"
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_pointers.c" \
  "$work_dir/pointers-stage0.o" -o "$work_dir/pointers-stage0"
"$work_dir/pointers-stage0"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_pointers.lisp" "$work_dir/pointers-repeat.o"
cmp "$work_dir/pointers.o" "$work_dir/pointers-repeat.o"

for source in "$project_root"/tests/bootstrap_pointer_errors/*.lisp; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" \
      "$source" "$work_dir/invalid-pointer.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted invalid pointer source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid-pointer.o"
done

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_parameter_calls.lisp" \
  "$work_dir/parameter-calls.o"
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_answer.c" \
  "$work_dir/parameter-calls.o" -o "$work_dir/parameter-calls"
"$work_dir/parameter-calls"
# LIR materializes argument expressions in frame slots before loading registers.
# The C caller checks nested calls; temporary evaluation pushes are no longer
# needed across call sites.

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_local_functions.lisp" \
  "$work_dir/local-functions.o"
nm -g --defined-only "$work_dir/local-functions.o" | grep -q ' answer$'
if nm -g --defined-only "$work_dir/local-functions.o" | \
    grep -q ' local_'; then
  echo 'native slice exported an internal Lisp function' >&2
  exit 1
fi
nm --defined-only "$work_dir/local-functions.o" | grep -q ' t local_before$'
nm --defined-only "$work_dir/local-functions.o" | grep -q ' t local_after$'
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_answer.c" \
  "$work_dir/local-functions.o" -o "$work_dir/local-functions"
"$work_dir/local-functions"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_forward_call.lisp" \
  "$work_dir/forward-call.o"
test "$(nm -u "$work_dir/forward-call.o" | wc -l)" -eq 0
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_answer.c" \
  "$work_dir/forward-call.o" -o "$work_dir/forward-call"
"$work_dir/forward-call"

if run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/examples/basic/add.lisp" "$work_dir/unsupported.o" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'native slice accepted unsupported source' >&2
  exit 1
fi
grep -q 'unsupported or malformed source' "$work_dir/stderr"
test ! -e "$work_dir/unsupported.o"

if run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_duplicate_exports.lisp" \
    "$work_dir/duplicate.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'native slice accepted duplicate export names' >&2
  exit 1
fi
test ! -e "$work_dir/duplicate.o"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_symbols.lisp" "$work_dir/symbols.o"
nm -g --defined-only "$work_dir/symbols.o" | grep -q ' T answer$'
nm --defined-only "$work_dir/symbols.o" | grep -q ' t helper-one$'
"$host_compiler" -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_symbols.c" \
  "$work_dir/symbols.o" -o "$work_dir/symbols$host_suffix"
run_host "$work_dir/symbols$host_suffix"
"$project_root/pslcc" --target="$host_target" -c \
  "$project_root/tests/bootstrap_symbols.lisp" \
  -o "$work_dir/symbols-stage0.o"
"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_symbols.c" \
  "$work_dir/symbols-stage0.o" -o "$work_dir/symbols-stage0$host_suffix"
run_host "$work_dir/symbols-stage0$host_suffix"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_symbols.lisp" "$work_dir/symbols-repeat.o"
cmp "$work_dir/symbols.o" "$work_dir/symbols-repeat.o"
for source in "$project_root"/tests/bootstrap_symbol_errors/*.lisp; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" "$source" \
      "$work_dir/invalid-symbol.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted invalid symbol identity source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid-symbol.o"
done

run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_uppercase_export.lisp" \
    "$work_dir/uppercase.o"
nm -g "$work_dir/uppercase.o" | grep -q ' T answer$'

run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_export_hyphen.lisp" \
    "$work_dir/export-hyphen.o"
nm -g "$work_dir/export-hyphen.o" | grep -q ' T exported-name$'

if run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_empty_call.lisp" \
    "$work_dir/empty-call.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'native slice accepted an empty call form' >&2
  exit 1
fi
test ! -e "$work_dir/empty-call.o"

if run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_wrong_arity.lisp" \
    "$work_dir/wrong-arity.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'native slice accepted a call with the wrong arity' >&2
  exit 1
fi
test ! -e "$work_dir/wrong-arity.o"

if run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_usize_cross_type.lisp" \
    "$work_dir/usize-cross-type.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'native slice accepted a mixed u64/usize call' >&2
  exit 1
fi
test ! -e "$work_dir/usize-cross-type.o"

for source in bootstrap_integer_range bootstrap_unsigned_negative; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" \
      "$project_root/tests/$source.lisp" "$work_dir/$source.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted an out-of-range integer: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/$source.o"
done

for source in bootstrap_mixed_operator bootstrap_mixed_argument bootstrap_cast_arity; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" \
      "$project_root/tests/$source.lisp" "$work_dir/$source.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted an invalid integer type relationship: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/$source.o"
done

if test "$host_target" != x86_64-linux-gnu; then
  "$project_root/pslcc" --target=x86_64-linux-gnu -c \
    "$project_root/bootstrap/native-core.lisp" \
    -o "$work_dir/native-reference-core.o"
  "$project_root/pslcc" -c "$project_root/bootstrap/host/driver.lisp" \
    -o "$work_dir/native-reference-host.o"
  "$project_root/pslcc" -c "$project_root/bootstrap/host/source_unit.lisp" \
    -o "$work_dir/native-reference-source.o"
  "$project_root/pslcc" -c "$project_root/bootstrap/host/source_io.lisp" \
    -o "$work_dir/native-reference-input.o"
  "$project_root/pslcc" -c "$project_root/bootstrap/host/source_path_posix.lisp" \
    -o "$work_dir/native-reference-path.o"
  "$project_root/pslcc" -c "$project_root/bootstrap/host/compiler.lisp" \
    -o "$work_dir/native-reference-driver.o"
  "$project_root/pslcc" -c "$project_root/bootstrap/host/output.lisp" \
    -o "$work_dir/native-reference-output.o"
  "$project_root/pslcc" -c "$project_root/bootstrap/host/diagnostics.lisp" \
    -o "$work_dir/native-reference-diagnostics.o"
  cc -Wall -Wextra -Werror "$project_root/bootstrap/driver.c" \
    "$project_root/bootstrap/host/platform_stdio.c" \
    "$project_root/bootstrap/host/platform_toolchain.c" \
    "$work_dir/native-reference-core.o" "$work_dir/native-reference-host.o" \
    "$work_dir/native-reference-source.o" "$work_dir/native-reference-input.o" \
    "$work_dir/native-reference-path.o" \
    "$work_dir/native-reference-driver.o" \
    "$work_dir/native-reference-output.o" \
    "$work_dir/native-reference-diagnostics.o" \
    -o "$work_dir/native-reference"
  "$work_dir/native-reference" "$project_root/bootstrap/host/compiler.lisp" \
    "$work_dir/native-driver-reference.o"
  cmp "$work_dir/native-driver-native.o" "$work_dir/native-driver-reference.o"
  "$work_dir/native-reference" "$project_root/bootstrap/host/output.lisp" \
    "$work_dir/native-output-reference.o"
  cmp "$work_dir/native-output-native.o" "$work_dir/native-output-reference.o"
  "$work_dir/native-reference" "$project_root/bootstrap/host/diagnostics.lisp" \
    "$work_dir/native-diagnostics-reference.o"
  cmp "$work_dir/native-diagnostics-native.o" \
    "$work_dir/native-diagnostics-reference.o"
  "$work_dir/native-reference" "$project_root/bootstrap/host/source_unit.lisp" \
    "$work_dir/native-source-reference.o"
  cmp "$work_dir/native-source-native.o" "$work_dir/native-source-reference.o"
  "$work_dir/native-reference" "$project_root/bootstrap/host/source_io.lisp" \
    "$work_dir/native-input-reference.o"
  cmp "$work_dir/native-input-native.o" "$work_dir/native-input-reference.o"
  "$work_dir/native-reference" "$project_root/$path_source" \
    "$work_dir/native-path-reference.o"
  cmp "$work_dir/native-path-native.o" "$work_dir/native-path-reference.o"
  "$work_dir/native-reference" "$project_root/bootstrap/host/driver.lisp" \
    "$work_dir/native-host-reference.o"
  cmp "$work_dir/native-host-native.o" "$work_dir/native-host-reference.o"
  "$work_dir/native-reference" "$project_root/tests/bootstrap_answer.lisp" \
    "$work_dir/native-reference.o"
  cmp "$work_dir/bootstrap_answer.o" "$work_dir/native-reference.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_two_functions.lisp" \
    "$work_dir/native-reference-two.o"
  cmp "$work_dir/two-functions.o" "$work_dir/native-reference-two.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_local_calls.lisp" \
    "$work_dir/native-reference-calls.o"
  cmp "$work_dir/local-calls.o" "$work_dir/native-reference-calls.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_parameter_calls.lisp" \
    "$work_dir/native-reference-parameter-calls.o"
  cmp "$work_dir/parameter-calls.o" \
    "$work_dir/native-reference-parameter-calls.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_six_arguments.lisp" \
    "$work_dir/native-reference-six-arguments.o"
  cmp "$work_dir/six-arguments.o" \
    "$work_dir/native-reference-six-arguments.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_usize.lisp" \
    "$work_dir/native-reference-usize.o"
  cmp "$work_dir/usize.o" "$work_dir/native-reference-usize.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_integer_types.lisp" \
    "$work_dir/native-reference-integer-types.o"
  cmp "$work_dir/integer-types.o" "$work_dir/native-reference-integer-types.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_mixed_integers.lisp" \
    "$work_dir/native-reference-mixed-integers.o"
  cmp "$work_dir/mixed-integers.o" "$work_dir/native-reference-mixed-integers.o"
  "$work_dir/native-reference" \
    "$project_root/bootstrap/ir/integer_types.lisp" \
    "$work_dir/native-reference-integer-module.o"
  cmp "$work_dir/integer-module.o" "$work_dir/native-reference-integer-module.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_local_functions.lisp" \
    "$work_dir/native-reference-local-functions.o"
  cmp "$work_dir/local-functions.o" \
    "$work_dir/native-reference-local-functions.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_forward_call.lisp" \
    "$work_dir/native-reference-forward-call.o"
  cmp "$work_dir/forward-call.o" \
    "$work_dir/native-reference-forward-call.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_recursion.lisp" \
    "$work_dir/native-reference-recursion.o"
  cmp "$work_dir/bootstrap_recursion.o" \
    "$work_dir/native-reference-recursion.o"
  for source in bootstrap_bitops bootstrap_lexical \
      bootstrap_declaration_order bootstrap_lisp_names bootstrap_symbols; do
    "$work_dir/native-reference" "$project_root/tests/$source.lisp" \
      "$work_dir/native-reference-$source.o"
    cmp "$work_dir/$source.o" "$work_dir/native-reference-$source.o"
  done
  "$work_dir/native-reference" "$project_root/tests/bootstrap_foreign_calls.lisp" \
    "$work_dir/foreign-reference.o"
  cmp "$work_dir/foreign-calls.o" "$work_dir/foreign-reference.o"
  "$work_dir/native-reference" "$project_root/tests/bootstrap_void_calls.lisp" \
    "$work_dir/void-reference.o"
  cmp "$work_dir/void-calls.o" "$work_dir/void-reference.o"
  "$work_dir/native-reference" "$project_root/tests/bootstrap_layout_queries.lisp" \
    "$work_dir/layout-queries-reference.o"
  cmp "$work_dir/layout-queries.o" "$work_dir/layout-queries-reference.o"
  "$work_dir/native-reference" "$project_root/tests/bootstrap_stack_arguments.lisp" \
    "$work_dir/stack-arguments-reference.o"
  cmp "$work_dir/stack-arguments.o" "$work_dir/stack-arguments-reference.o"
  for module in binary arena reader atoms; do
    "$work_dir/native-reference" "$(module_source "$module")" \
      "$work_dir/$module-module-reference.o"
    cmp "$work_dir/$module-module.o" "$work_dir/$module-module-reference.o"
  done
  "$work_dir/native-reference" "$project_root/tests/bootstrap_pointers.lisp" \
    "$work_dir/pointers-reference.o"
  cmp "$work_dir/pointers.o" "$work_dir/pointers-reference.o"
fi

"$project_root/pslcc" -O0 --target="$host_target" -c \
  "$project_root/bootstrap/native-core.lisp" \
  -o "$work_dir/native-core-O0.o"
"$project_root/pslcc" -O0 --target="$host_target" -c \
  "$project_root/bootstrap/host/driver.lisp" -o "$work_dir/native-host-O0.o"
"$project_root/pslcc" -O0 --target="$host_target" -c \
  "$project_root/bootstrap/host/source_unit.lisp" -o "$work_dir/native-source-O0.o"
"$project_root/pslcc" -O0 --target="$host_target" -c \
  "$project_root/bootstrap/host/source_io.lisp" -o "$work_dir/native-input-O0.o"
"$project_root/pslcc" -O0 --target="$host_target" -c \
  "$project_root/$path_source" -o "$work_dir/native-path-O0.o"
"$project_root/pslcc" -O0 --target="$host_target" -c \
  "$project_root/bootstrap/host/compiler.lisp" -o "$work_dir/native-driver-O0.o"
"$project_root/pslcc" -O0 --target="$host_target" -c \
  "$project_root/bootstrap/host/output.lisp" -o "$work_dir/native-output-O0.o"
"$project_root/pslcc" -O0 --target="$host_target" -c \
  "$project_root/bootstrap/host/diagnostics.lisp" \
  -o "$work_dir/native-diagnostics-O0.o"
"$host_compiler" -Wall -Wextra -Werror $allocator_flags \
  "$project_root/tests/harness_bootstrap_compiler.c" "$work_dir/native-driver-O0.o" \
  -o "$work_dir/compiler-driver-O0-check$host_suffix"
run_host "$work_dir/compiler-driver-O0-check$host_suffix"
"$host_compiler" -Wall -Wextra -Werror $source_allocator_flags \
  "$project_root/tests/harness_bootstrap_source_unit.c" \
  "$work_dir/native-core-O0.o" "$work_dir/native-source-O0.o" -o "$work_dir/source-unit-O0-check$host_suffix"
run_host "$work_dir/source-unit-O0-check$host_suffix"
"$host_compiler" -Wall -Wextra -Werror $allocator_flags \
  "$project_root/tests/harness_bootstrap_driver.c" \
  "$work_dir/native-core-O0.o" "$work_dir/native-host-O0.o" -o "$work_dir/driver-O0-check$host_suffix"
run_host "$work_dir/driver-O0-check$host_suffix"
"$host_compiler" -Wall -Wextra -Werror "$project_root/bootstrap/driver.c" \
  "$project_root/bootstrap/host/platform_stdio.c" \
  "$project_root/bootstrap/host/platform_toolchain.c" \
  "$work_dir/native-core-O0.o" "$work_dir/native-host-O0.o" "$work_dir/native-source-O0.o" \
  "$work_dir/native-input-O0.o" "$work_dir/native-path-O0.o" \
  "$work_dir/native-driver-O0.o" "$work_dir/native-output-O0.o" \
  "$work_dir/native-diagnostics-O0.o" -o "$work_dir/pslcc-native-O0$host_suffix"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/bootstrap/host/compiler.lisp" "$work_dir/native-driver-native-O0.o"
cmp "$work_dir/native-driver-native.o" "$work_dir/native-driver-native-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/bootstrap/host/output.lisp" "$work_dir/native-output-native-O0.o"
cmp "$work_dir/native-output-native.o" "$work_dir/native-output-native-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/bootstrap/host/diagnostics.lisp" \
  "$work_dir/native-diagnostics-native-O0.o"
cmp "$work_dir/native-diagnostics-native.o" \
  "$work_dir/native-diagnostics-native-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/bootstrap/host/source_unit.lisp" "$work_dir/native-source-native-O0.o"
cmp "$work_dir/native-source-native.o" "$work_dir/native-source-native-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/bootstrap/host/source_io.lisp" "$work_dir/native-input-native-O0.o"
cmp "$work_dir/native-input-native.o" "$work_dir/native-input-native-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/$path_source" "$work_dir/native-path-native-O0.o"
cmp "$work_dir/native-path-native.o" "$work_dir/native-path-native-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/bootstrap/host/driver.lisp" "$work_dir/native-host-native-O0.o"
cmp "$work_dir/native-host-native.o" "$work_dir/native-host-native-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_forward_call.lisp" \
  "$work_dir/forward-call-O0.o"
cmp "$work_dir/forward-call.o" "$work_dir/forward-call-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_recursion.lisp" \
  "$work_dir/recursion-O0.o"
cmp "$work_dir/bootstrap_recursion.o" "$work_dir/recursion-O0.o"
for source in bootstrap_bitops bootstrap_lexical \
    bootstrap_declaration_order bootstrap_lisp_names bootstrap_symbols; do
  run_host "$work_dir/pslcc-native-O0$host_suffix" \
    "$project_root/tests/$source.lisp" "$work_dir/$source-O0.o"
  cmp "$work_dir/$source.o" "$work_dir/$source-O0.o"
done
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_six_arguments.lisp" \
  "$work_dir/six-arguments-O0.o"
cmp "$work_dir/six-arguments.o" "$work_dir/six-arguments-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_usize.lisp" \
  "$work_dir/usize-O0.o"
cmp "$work_dir/usize.o" "$work_dir/usize-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_integer_types.lisp" \
  "$work_dir/integer-types-O0.o"
cmp "$work_dir/integer-types.o" "$work_dir/integer-types-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_mixed_integers.lisp" \
  "$work_dir/mixed-integers-O0.o"
cmp "$work_dir/mixed-integers.o" "$work_dir/mixed-integers-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/bootstrap/ir/integer_types.lisp" \
  "$work_dir/integer-module-O0.o"
cmp "$work_dir/integer-module.o" "$work_dir/integer-module-O0.o"

for module in binary arena reader atoms; do
  run_host "$work_dir/pslcc-native-O0$host_suffix" \
    "$(module_source "$module")" "$work_dir/$module-module-O0.o"
  cmp "$work_dir/$module-module.o" "$work_dir/$module-module-O0.o"
done
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_pointers.lisp" "$work_dir/pointers-O0.o"
cmp "$work_dir/pointers.o" "$work_dir/pointers-O0.o"

run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_stack_arguments.lisp" "$work_dir/stack-arguments-O0.o"
cmp "$work_dir/stack-arguments.o" "$work_dir/stack-arguments-O0.o"

run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_foreign_calls.lisp" "$work_dir/foreign-O0.o"
cmp "$work_dir/foreign-calls.o" "$work_dir/foreign-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_void_calls.lisp" "$work_dir/void-O0.o"
cmp "$work_dir/void-calls.o" "$work_dir/void-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_layout_queries.lisp" "$work_dir/layout-queries-O0.o"
cmp "$work_dir/layout-queries.o" "$work_dir/layout-queries-O0.o"

PSL_NATIVE_COMPILER_HOST_TARGET=$host_target \
  sh "$project_root/tests/bootstrap_environment.sh" \
    "$work_dir/pslcc-native-slice$host_suffix" "$host_target"

if test -n "${PSL_NATIVE_OBJECT_SNAPSHOT_DIR:-}"; then
  mkdir -p "$PSL_NATIVE_OBJECT_SNAPSHOT_DIR"
  for object in "$work_dir"/*.o; do
    case ${object##*/} in native-core.o|native-host.o|native-source.o|native-input.o|native-path.o|native-driver.o|native-output.o|native-diagnostics.o) continue ;; esac
    cp "$object" "$PSL_NATIVE_OBJECT_SNAPSHOT_DIR/${object##*/}"
  done
fi

echo "PSL native source-to-object compiler slice passed on $host_target"
