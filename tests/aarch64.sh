#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
target=aarch64-linux-gnu
sysroot=${AARCH64_SYSROOT:-/usr/aarch64-linux-gnu}

for tool in aarch64-linux-gnu-gcc aarch64-linux-gnu-readelf \
            aarch64-linux-gnu-nm aarch64-linux-gnu-ar qemu-aarch64; do
  command -v "$tool" >/dev/null
done

run_target() {
  qemu-aarch64 -L "$sysroot" "$@"
}

compile_case() {
  name=$1
  source=$2
  harness=$3
  for level in 0 1; do
    object="$work_dir/$name-O$level.o"
    "$project_root/pslcc" --target="$target" "-O$level" -c \
      "$project_root/examples/$source.lisp" -o "$object"
    aarch64-linux-gnu-gcc "$project_root/examples/$harness.c" \
      "$object" -o "$work_dir/$name-O$level"
    run_target "$work_dir/$name-O$level"
  done
}

compile_case add basic/add basic/harness_add
compile_case void abi/void abi/harness_void
compile_case float abi/float abi/harness_float
compile_case aggregate abi/aggregate abi/harness_aggregate
compile_case hfa abi/aarch64_hfa abi/harness_aarch64_hfa
compile_case stack abi/stack abi/harness_stack
compile_case layout abi/layout abi/harness_layout
compile_case memory memory/memory memory/harness_memory
compile_case data_import ffi/data_import ffi/harness_data_import
compile_case source_import ffi/source_import ffi/harness_source_import

"$project_root/pslcc" --target="$target" -c \
  "$project_root/examples/basic/add.lisp" -o "$work_dir/repeat.o"
cmp "$work_dir/add-O1.o" "$work_dir/repeat.o"
aarch64-linux-gnu-readelf -h "$work_dir/add-O1.o" |
  grep -q 'Machine:.*AArch64'
aarch64-linux-gnu-readelf -Wr "$work_dir/add-O1.o" |
  grep -q 'R_AARCH64_CALL26'
aarch64-linux-gnu-readelf -Wr "$work_dir/data_import-O1.o" |
  grep -q 'R_AARCH64_ADR_GOT_PAGE'
aarch64-linux-gnu-readelf -Wr "$work_dir/data_import-O1.o" |
  grep -q 'R_AARCH64_LD64_GOT_LO12_NC'
aarch64-linux-gnu-nm -g "$work_dir/add-O1.o" | grep -q ' T add'

for example in arithmetic recursion macros layout no_allocation; do
  for level in 0 1; do
    "$project_root/pslcc" --target="$target" "-O$level" \
      "$project_root/examples/native/$example.lisp" \
      -o "$work_dir/native-$example-O$level"
    run_target "$work_dir/native-$example-O$level"
  done
done
test -z "$(aarch64-linux-gnu-nm "$work_dir/native-arithmetic-O1" |
  grep psl_rt_ || true)"

for example in immediate list gc_list string_package closure multiple_values; do
  for level in 0 1; do
    "$project_root/pslcc" --target="$target" --profile=hosted "-O$level" \
      "$project_root/examples/hosted/$example.lisp" \
      -o "$work_dir/hosted-$example-O$level"
    run_target "$work_dir/hosted-$example-O$level"
  done
done
aarch64-linux-gnu-nm "$work_dir/hosted-list-O1" | grep -q ' T psl_rt_cons'
test -z "$(aarch64-linux-gnu-nm "$work_dir/hosted-list-O1" |
  grep ' T psl_rt_make_string' || true)"

"$project_root/pslcc" --target="$target" --emit=static \
  "$project_root/examples/basic/standalone.lisp" -o "$work_dir/libpsl.a"
aarch64-linux-gnu-ar t "$work_dir/libpsl.a" | grep -q psl.o
aarch64-linux-gnu-gcc "$project_root/examples/basic/harness_standalone.c" \
  "$work_dir/libpsl.a" -o "$work_dir/static-harness"
run_target "$work_dir/static-harness"
cp "$work_dir/libpsl.a" "$work_dir/libpsl-first.a"
"$project_root/pslcc" --target="$target" --emit=static \
  "$project_root/examples/basic/standalone.lisp" -o "$work_dir/libpsl.a"
cmp "$work_dir/libpsl-first.a" "$work_dir/libpsl.a"

"$project_root/pslcc" --target="$target" --emit=shared \
  "$project_root/examples/basic/standalone.lisp" -o "$work_dir/libpsl.so"
aarch64-linux-gnu-gcc "$project_root/examples/basic/harness_standalone.c" \
  "$work_dir/libpsl.so" -Wl,-rpath,"$work_dir" \
  -o "$work_dir/shared-harness"
run_target "$work_dir/shared-harness"

"$project_root/pslcc" --target="$target" --emit=shared \
  "$project_root/examples/ffi/shared_data.lisp" \
  -o "$work_dir/libpsl-data.so"
"$project_root/pslcc" --target="$target" --emit=shared \
  "$project_root/examples/ffi/shared_data.lisp" \
  -o "$work_dir/libpsl-data-again.so"
cmp "$work_dir/libpsl-data.so" "$work_dir/libpsl-data-again.so"
aarch64-linux-gnu-gcc "$project_root/examples/ffi/harness_shared_data.c" \
  "$work_dir/libpsl-data.so" -Wl,-rpath,"$work_dir" \
  -o "$work_dir/shared-data-harness"
run_target "$work_dir/shared-data-harness"

"$project_root/pslcc" --target="$target" --emit=shared \
  "$project_root/examples/ffi/source_import.lisp" \
  -o "$work_dir/libpsl-ffi.so"
aarch64-linux-gnu-gcc "$project_root/examples/ffi/harness_source_import.c" \
  "$work_dir/libpsl-ffi.so" -Wl,-rpath,"$work_dir" \
  -o "$work_dir/shared-ffi-harness"
run_target "$work_dir/shared-ffi-harness"

echo 'AArch64 Linux tests passed'
