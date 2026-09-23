#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
sysroot=${RISCV64_SYSROOT:-/usr/riscv64-linux-gnu}

for tool in riscv64-linux-gnu-gcc riscv64-linux-gnu-readelf \
            riscv64-linux-gnu-nm riscv64-linux-gnu-ar \
            riscv64-unknown-elf-ld qemu-riscv64 qemu-x86_64 \
            qemu-system-riscv64 timeout; do
  command -v "$tool" >/dev/null
done

run_linux() {
  qemu-riscv64 -L "$sysroot" "$@"
}

compile_case() {
  name=$1
  source=$2
  harness=$3
  for level in 0 1; do
    object="$work_dir/$name-O$level.o"
    "$project_root/pslcc" --target=riscv64-linux-gnu "-O$level" -c \
      "$project_root/examples/$source.lisp" -o "$object"
    riscv64-linux-gnu-gcc "$project_root/examples/$harness.c" \
      "$object" -o "$work_dir/$name-O$level"
    run_linux "$work_dir/$name-O$level"
  done
}

compile_case add basic/add basic/harness_add
compile_case void abi/void abi/harness_void
compile_case float abi/float abi/harness_float
compile_case aggregate abi/aggregate abi/harness_aggregate
compile_case edges abi/riscv64_edges abi/harness_riscv64_edges
compile_case stack abi/stack abi/harness_stack
compile_case layout abi/layout abi/harness_layout
compile_case memory memory/memory memory/harness_memory
compile_case data_import ffi/data_import ffi/harness_data_import
compile_case source_import ffi/source_import ffi/harness_source_import

"$project_root/pslcc" --target=riscv64-linux-gnu -c \
  "$project_root/examples/basic/add.lisp" -o "$work_dir/repeat.o"
cmp "$work_dir/add-O1.o" "$work_dir/repeat.o"
riscv64-linux-gnu-readelf -h "$work_dir/add-O1.o" |
  grep -q 'Machine:.*RISC-V'
riscv64-linux-gnu-readelf -h "$work_dir/add-O1.o" |
  grep -q 'double-float ABI'
riscv64-linux-gnu-readelf -Wr "$work_dir/add-O1.o" |
  grep -q 'R_RISCV_CALL_PLT'
riscv64-linux-gnu-readelf -Wr "$work_dir/data_import-O1.o" |
  grep -q 'R_RISCV_GOT_HI20'
riscv64-linux-gnu-readelf -Wr "$work_dir/data_import-O1.o" |
  grep -q 'R_RISCV_PCREL_LO12_I'

for example in arithmetic recursion macros layout no_allocation; do
  for level in 0 1; do
    "$project_root/pslcc" --target=riscv64-linux-gnu "-O$level" \
      "$project_root/examples/native/$example.lisp" \
      -o "$work_dir/native-$example-O$level"
    run_linux "$work_dir/native-$example-O$level"
  done
done
test -z "$(riscv64-linux-gnu-nm "$work_dir/native-arithmetic-O1" |
  grep psl_rt_ || true)"

for example in immediate list gc_list string_package closure multiple_values; do
  for level in 0 1; do
    "$project_root/pslcc" --target=riscv64-linux-gnu --profile=hosted \
      "-O$level" "$project_root/examples/hosted/$example.lisp" \
      -o "$work_dir/hosted-$example-O$level"
    run_linux "$work_dir/hosted-$example-O$level"
  done
done
riscv64-linux-gnu-nm "$work_dir/hosted-list-O1" | grep -q ' T psl_rt_cons'
test -z "$(riscv64-linux-gnu-nm "$work_dir/hosted-list-O1" |
  grep ' T psl_rt_make_string' || true)"

"$project_root/pslcc" --target=riscv64-linux-gnu --emit=static \
  "$project_root/examples/basic/standalone.lisp" -o "$work_dir/libpsl.a"
riscv64-linux-gnu-ar t "$work_dir/libpsl.a" | grep -q psl.o
riscv64-linux-gnu-gcc "$project_root/examples/basic/harness_standalone.c" \
  "$work_dir/libpsl.a" -o "$work_dir/static-harness"
run_linux "$work_dir/static-harness"
cp "$work_dir/libpsl.a" "$work_dir/libpsl-first.a"
"$project_root/pslcc" --target=riscv64-linux-gnu --emit=static \
  "$project_root/examples/basic/standalone.lisp" -o "$work_dir/libpsl.a"
cmp "$work_dir/libpsl-first.a" "$work_dir/libpsl.a"

"$project_root/pslcc" --target=riscv64-linux-gnu --emit=shared \
  "$project_root/examples/ffi/shared_data.lisp" \
  -o "$work_dir/libpsl-data.so"
"$project_root/pslcc" --target=riscv64-linux-gnu --emit=shared \
  "$project_root/examples/ffi/shared_data.lisp" \
  -o "$work_dir/libpsl-data-again.so"
cmp "$work_dir/libpsl-data.so" "$work_dir/libpsl-data-again.so"
riscv64-linux-gnu-gcc "$project_root/examples/ffi/harness_shared_data.c" \
  "$work_dir/libpsl-data.so" -Wl,-rpath,"$work_dir" \
  -o "$work_dir/shared-data-harness"
run_linux "$work_dir/shared-data-harness"

"$project_root/pslcc" --target=x86_64-none-elf --startup=linux-exit \
  --map="$work_dir/x86.map" "$project_root/examples/native/arithmetic.lisp" \
  -o "$work_dir/x86-freestanding"
qemu-x86_64 "$work_dir/x86-freestanding"
test -z "$(nm -u "$work_dir/x86-freestanding")"
test -z "$(readelf -d "$work_dir/x86-freestanding" |
  grep NEEDED || true)"
test "$(grep -c '^LOAD ' "$work_dir/x86.map")" = 2
test -z "$(grep -E 'libc|psl_rt_' "$work_dir/x86.map" || true)"
sed 's/0x400000/0x500000/' \
  "$project_root/linker/x86_64-linux-user.ld" > "$work_dir/x86-custom.ld"
"$project_root/pslcc" --target=x86_64-none-elf --startup=linux-exit \
  --linker-script="$work_dir/x86-custom.ld" \
  "$project_root/examples/native/arithmetic.lisp" \
  -o "$work_dir/x86-custom"
readelf -h "$work_dir/x86-custom" | grep -q 'Entry point address:.*0x500000'
qemu-x86_64 "$work_dir/x86-custom"
"$project_root/pslcc" --target=x86_64-none-elf --entry=main \
  "$project_root/examples/basic/program.lisp" -o "$work_dir/x86-entry"
readelf -h "$work_dir/x86-entry" |
  grep -q 'Entry point address:.*0x400000'

"$project_root/pslcc" --target=riscv64-none-elf --startup=qemu-virt \
  --map="$work_dir/virt.map" \
  "$project_root/examples/native/arithmetic.lisp" \
  -o "$work_dir/virt-freestanding"
timeout 15s qemu-system-riscv64 -machine virt -m 128M -nographic \
  -bios none -kernel "$work_dir/virt-freestanding" -no-reboot
test -z "$(riscv64-linux-gnu-nm -u "$work_dir/virt-freestanding")"
test -z "$(riscv64-linux-gnu-readelf -d "$work_dir/virt-freestanding" |
  grep NEEDED || true)"
test "$(grep -c '^LOAD ' "$work_dir/virt.map")" = 2
test -z "$(grep -E 'libc|psl_rt_' "$work_dir/virt.map" || true)"
"$project_root/pslcc" --target=riscv64-none-elf --startup=qemu-virt \
  --linker-script="$project_root/linker/riscv64-virt.ld" \
  "$project_root/examples/native/arithmetic.lisp" \
  -o "$work_dir/virt-explicit-script"
cmp "$work_dir/virt-freestanding" "$work_dir/virt-explicit-script"
timeout 15s qemu-system-riscv64 -machine virt -m 128M -nographic \
  -bios none -kernel "$work_dir/virt-explicit-script" -no-reboot
"$project_root/pslcc" --target=riscv64-none-elf --startup=qemu-virt \
  "$project_root/examples/native/macros.lisp" \
  -o "$work_dir/virt-macros"
timeout 15s qemu-system-riscv64 -machine virt -m 128M -nographic \
  -bios none -kernel "$work_dir/virt-macros" -no-reboot
"$project_root/pslcc" --target=riscv64-none-elf --startup=qemu-virt \
  "$project_root/examples/freestanding/virt_uart.lisp" \
  -o "$work_dir/virt-uart"
uart_output=$(timeout 15s qemu-system-riscv64 -machine virt -m 128M \
  -nographic -bios none -kernel "$work_dir/virt-uart" -no-reboot)
test "$uart_output" = P

"$project_root/pslcc" --target=riscv64-none-elf --startup=qemu-virt \
  "$project_root/tests/freestanding_fail.lisp" \
  -o "$work_dir/virt-failure"
set +e
timeout 15s qemu-system-riscv64 -machine virt -m 128M -nographic \
  -bios none -kernel "$work_dir/virt-failure" -no-reboot
failure_status=$?
set -e
test "$failure_status" -eq 1

echo 'RISC-V Linux and freestanding tests passed'
