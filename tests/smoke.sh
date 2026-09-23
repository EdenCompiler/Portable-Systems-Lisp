#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

"$project_root/pslcc" -c "$project_root/examples/add.lisp" -o "$work_dir/first.o"
"$project_root/pslcc" -c "$project_root/examples/add.lisp" -o "$work_dir/second.o"
cmp "$work_dir/first.o" "$work_dir/second.o"

readelf -h "$work_dir/first.o" | grep -q 'REL (Relocatable file)'
readelf -r "$work_dir/first.o" | grep -q 'R_X86_64_PLT32'
cc "$project_root/examples/harness.c" "$work_dir/first.o" -o "$work_dir/harness"
"$work_dir/harness"

"$project_root/pslcc" -c "$project_root/examples/memory.lisp" \
  -o "$work_dir/memory.o"
cc "$project_root/examples/harness_memory.c" "$work_dir/memory.o" \
  -o "$work_dir/memory-harness"
"$work_dir/memory-harness"
test -z "$(nm -u "$work_dir/memory.o")"

"$project_root/pslcc" -c "$project_root/examples/ffi_source.lisp" \
  -o "$work_dir/ffi-source.o"
"$project_root/pslcc" -c "$project_root/examples/ffi_source.lisp" \
  -o "$work_dir/ffi-source-again.o"
cmp "$work_dir/ffi-source.o" "$work_dir/ffi-source-again.o"
test -z "$(nm -u "$work_dir/ffi-source.o")"
cc "$project_root/examples/harness_ffi_source.c" "$work_dir/ffi-source.o" \
  -o "$work_dir/ffi-source-harness"
"$work_dir/ffi-source-harness"

"$project_root/pslcc" --target=x86_64-none-elf --profile=freestanding \
  -c "$project_root/examples/standalone.lisp" -o "$work_dir/standalone.o"
test -z "$(nm -u "$work_dir/standalone.o")"

sbcl --script "$project_root/tests/library.lisp" \
  "$project_root/examples/standalone.lisp" "$work_dir/library.o"
cmp "$work_dir/standalone.o" "$work_dir/library.o"

sh "$project_root/tests/negative.sh"

printf 'PSL smoke test passed\n'
