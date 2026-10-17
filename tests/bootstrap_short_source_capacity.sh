#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target_filter=${2:-all}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
cross_root=${PSL_CROSS_ROOT:-$project_root/../m8-cross-tools}
if test -d "$cross_root"; then
  PATH="$cross_root/bin:$cross_root/usr/bin:$PATH"
  LD_LIBRARY_PATH="$cross_root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  AARCH64_SYSROOT=${AARCH64_SYSROOT:-$cross_root/usr/aarch64-linux-gnu}
  RISCV64_SYSROOT=${RISCV64_SYSROOT:-$cross_root/usr/riscv64-linux-gnu}
  export PATH LD_LIBRARY_PATH AARCH64_SYSROOT RISCV64_SYSROOT
fi

data_source=$project_root/examples/ffi/data_only.lisp
empty_source=$work_dir/empty.lisp
invalid_source=$work_dir/invalid.lisp
short_import=$work_dir/short-import.lisp
short_typed=$work_dir/short-typed.lisp
short_noarg=$work_dir/short-noarg.lisp
printf '(defun bad (\n' >"$invalid_source"
: >"$short_import"
printf '%s\n' '(ffi:import-function "f" ((x u8)) -> u8)' >"$short_import"
: >"$empty_source"
# This 45-byte, one-parameter function exercises the minimum driver capacity
# boundary: the CLI passes source length + 1, which must leave 45 runtime
# catalogue parameter slots after the one source parameter.
printf '%s' '(defun f(x)(declare(type u8 x)(returns u8))x)' >"$short_typed"
test "$(wc -c <"$short_typed")" -eq 45
printf '%s' '(defun f()(declare(returns u8))0)' >"$short_noarg"
test "$(wc -c <"$short_noarg")" -eq 33

for target in x86_64-linux-gnu x86_64-windows-gnu aarch64-linux-gnu riscv64-linux-gnu; do
  if test "$target_filter" != all && test "$target_filter" != "$target"; then
    continue
  fi
  bootstrap_test_runner_init "$target"
  for level in 0 1; do
    native_data=$work_dir/native-$target-data-O$level.o
    seed_data=$work_dir/seed-$target-data-O$level.o
    native_typed=$work_dir/native-$target-typed-O$level.o
    seed_typed=$work_dir/seed-$target-typed-O$level.o
    native_noarg=$work_dir/native-$target-noarg-O$level.o
    seed_noarg=$work_dir/seed-$target-noarg-O$level.o
    "$compiler" "-O$level" --profile=hosted --target="$target" -c \
      "$data_source" -o "$native_data"
    "$compiler" "-O$level" --profile=hosted --target="$target" -c \
      "$data_source" -o "$work_dir/native-$target-data-repeat-O$level.o"
    "$project_root/pslcc" "-O$level" --profile=hosted --target="$target" -c \
      "$data_source" -o "$seed_data"
    test -s "$native_data"
    test -s "$seed_data"
    cmp "$native_data" "$work_dir/native-$target-data-repeat-O$level.o"
    nm "$native_data" | grep -q ' psl_only$'
    nm "$seed_data" | grep -q ' psl_only$'
    "$compiler" "-O$level" --profile=hosted --target="$target" -c \
      "$short_typed" -o "$native_typed"
    "$project_root/pslcc" "-O$level" --profile=hosted --target="$target" -c \
      "$short_typed" -o "$seed_typed"
    test -s "$native_typed"
    test -s "$seed_typed"
    nm "$native_typed" | grep -q ' f$'
    nm "$seed_typed" | grep -q ' f$'
    "$compiler" "-O$level" --profile=hosted --target="$target" -c \
      "$short_noarg" -o "$native_noarg"
    "$project_root/pslcc" "-O$level" --profile=hosted --target="$target" -c \
      "$short_noarg" -o "$seed_noarg"
    test -s "$native_noarg"
    test -s "$seed_noarg"
    nm "$native_noarg" | grep -q ' f$'
    nm "$seed_noarg" | grep -q ' f$'
    for mode in native seed; do
      output=$work_dir/$mode-$target-empty-O$level.o
      if test "$mode" = native; then
        if "$compiler" "-O$level" --profile=hosted --target="$target" -c \
            "$empty_source" -o "$output" >"$work_dir/empty-out" 2>"$work_dir/empty-err"; then
          echo "native compiler accepted empty source for $target" >&2
          exit 1
        else
          status=$?
          test "$status" -eq 1
        fi
      elif "$project_root/pslcc" "-O$level" --profile=hosted --target="$target" -c \
          "$empty_source" -o "$output" >"$work_dir/empty-out" 2>"$work_dir/empty-err"; then
        echo "Stage 0 accepted empty source for $target" >&2
        exit 1
      else
        status=$?
        test "$status" -eq 1
      fi
      test ! -e "$output"
    done
    for mode in native seed; do
      output=$work_dir/$mode-$target-import-only-O$level.o
      if test "$mode" = native; then
        if "$compiler" "-O$level" --profile=hosted --target="$target" -c \
            "$short_import" -o "$output" >"$work_dir/import-out" 2>"$work_dir/import-err"; then
          echo "native compiler accepted import-only source for $target" >&2
          exit 1
        else
          status=$?
          test "$status" -eq 1
        fi
      elif "$project_root/pslcc" "-O$level" --profile=hosted --target="$target" -c \
          "$short_import" -o "$output" >"$work_dir/import-out" 2>"$work_dir/import-err"; then
        echo "Stage 0 accepted import-only source for $target" >&2
        exit 1
      else
        status=$?
        test "$status" -eq 1
      fi
      test ! -e "$output"
    done
  done
  # The exported byte is observable through ordinary C at both optimization
  # levels on every hosted target.
  for level in 0 1; do
    for mode in native seed; do
      for c_level in 0 2; do
        "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
          "$project_root/tests/bootstrap_short_source_data_harness.c" \
          "$work_dir/$mode-$target-data-O$level.o" \
          -o "$work_dir/data-harness-$mode-$target-O$level-C$c_level$target_suffix"
        run_target "$work_dir/data-harness-$mode-$target-O$level-C$c_level$target_suffix"
      done
    done
  done
done

# Runtime catalogue reservation is profile-specific; freestanding still accepts
# the small data-only program without changing the exact-capacity driver API.
for level in 0 1; do
  "$compiler" "-O$level" --profile=freestanding --target=x86_64-none-elf -c \
    "$data_source" -o "$work_dir/freestanding-O$level.o"
  "$project_root/pslcc" "-O$level" --profile=freestanding --target=x86_64-none-elf -c \
    "$data_source" -o "$work_dir/seed-freestanding-O$level.o"
  cmp "$work_dir/freestanding-O$level.o" "$work_dir/seed-freestanding-O$level.o"
done

# Preserve pre-existing output on a genuine source failure.
printf 'keep this output intact\n' >"$work_dir/preserved.o"
cp "$work_dir/preserved.o" "$work_dir/expected.o"
if "$compiler" --profile=hosted --target=x86_64-linux-gnu -c \
    "$invalid_source" -o "$work_dir/preserved.o" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'native compiler accepted malformed short-source fixture' >&2
  exit 1
else
  status=$?
  test "$status" -eq 1
fi
cmp "$work_dir/preserved.o" "$work_dir/expected.o"

echo 'short-source hosted catalogue capacity passed'
