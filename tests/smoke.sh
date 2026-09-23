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

"$project_root/pslcc" -O0 -c "$project_root/examples/add.lisp" \
  -o "$work_dir/add-O0.o"
cc "$project_root/examples/harness.c" "$work_dir/add-O0.o" \
  -o "$work_dir/add-O0-harness"
"$work_dir/add-O0-harness"

"$project_root/pslcc" -c "$project_root/examples/memory.lisp" \
  -o "$work_dir/memory.o"
cc "$project_root/examples/harness_memory.c" "$work_dir/memory.o" \
  -o "$work_dir/memory-harness"
"$work_dir/memory-harness"
test -z "$(nm -u "$work_dir/memory.o")"

"$project_root/pslcc" -O0 -c "$project_root/examples/memory.lisp" \
  -o "$work_dir/memory-O0.o"
cc "$project_root/examples/harness_memory.c" "$work_dir/memory-O0.o" \
  -o "$work_dir/memory-O0-harness"
"$work_dir/memory-O0-harness"

"$project_root/pslcc" -c "$project_root/examples/ffi_source.lisp" \
  -o "$work_dir/ffi-source.o"
"$project_root/pslcc" -c "$project_root/examples/ffi_source.lisp" \
  -o "$work_dir/ffi-source-again.o"
cmp "$work_dir/ffi-source.o" "$work_dir/ffi-source-again.o"
test -z "$(nm -u "$work_dir/ffi-source.o")"
cc "$project_root/examples/harness_ffi_source.c" "$work_dir/ffi-source.o" \
  -o "$work_dir/ffi-source-harness"
"$work_dir/ffi-source-harness"

"$project_root/pslcc" -O0 -c "$project_root/examples/ffi_source.lisp" \
  -o "$work_dir/ffi-source-O0.o"
cc "$project_root/examples/harness_ffi_source.c" \
  "$work_dir/ffi-source-O0.o" -o "$work_dir/ffi-source-O0-harness"
"$work_dir/ffi-source-O0-harness"

for level in 0 1; do
  "$project_root/pslcc" "-O$level" -c \
    "$project_root/examples/optimizer.lisp" \
    -o "$work_dir/optimizer-O$level.o"
  cc "$project_root/examples/harness_optimizer.c" \
    "$work_dir/optimizer-O$level.o" \
    -o "$work_dir/optimizer-O$level"
  "$work_dir/optimizer-O$level"
  "$project_root/pslcc" "-O$level" --dump-ir=lir -c \
    "$project_root/examples/optimizer.lisp" -o "$work_dir/dump-O$level.o" \
    >"$work_dir/dump-O$level.txt"
  cmp "$work_dir/optimizer-O$level.o" "$work_dir/dump-O$level.o"
done

readelf -r "$work_dir/optimizer-O0.o" | grep -q 'increment'
if readelf -r "$work_dir/optimizer-O1.o" | grep -q 'increment'; then
  printf 'Expected the local increment call to be inlined\n' >&2
  exit 1
fi
readelf -r "$work_dir/optimizer-O1.o" | grep -q 'side_effect_c'
awk '/^LIR discard_pure / { in_function=1; next }
     /^LIR / { in_function=0 }
     in_function && /BINARY/ { found=1 }
     END { exit !found }' "$work_dir/dump-O0.txt"
awk '/^LIR discard_pure / { in_function=1; next }
     /^LIR / { in_function=0 }
     in_function && /BINARY/ { found=1 }
     END { exit found }' "$work_dir/dump-O1.txt"
awk '/^LIR volatile_discard / { in_function=1; next }
     /^LIR / { in_function=0 }
     in_function && /LOAD/ { found=1 }
     END { exit !found }' "$work_dir/dump-O1.txt"

"$project_root/pslcc" -O1 --dump-ir=all -c \
  "$project_root/examples/optimizer.lisp" -o "$work_dir/all-dumps.o" \
  >"$work_dir/all-dumps.txt"
grep -q '^HIR constant_wrap ' "$work_dir/all-dumps.txt"
grep -q '^SSA constant_wrap ' "$work_dir/all-dumps.txt"
grep -q '^LIR constant_wrap ' "$work_dir/all-dumps.txt"
awk '/^SSA constant_wrap / { in_function=1; next }
     /^SSA / { in_function=0 }
     in_function && /CONSTANT :U8 value=4/ { found=1 }
     END { exit !found }' "$work_dir/all-dumps.txt"
"$project_root/pslcc" -O0 --dump-ir=ssa -c \
  "$project_root/examples/add.lisp" -o "$work_dir/ssa-joins.o" \
  >"$work_dir/ssa-joins.txt"
grep -q 'PHI :U64' "$work_dir/ssa-joins.txt"

sbcl --script "$project_root/tests/ir_verifier.lisp"

if "$project_root/pslcc" -c "$project_root/tests/diagnostics.lisp" \
    -o "$work_dir/invalid.o" >"$work_dir/diagnostic-out" \
    2>"$work_dir/diagnostic-err"; then
  printf 'Expected source diagnostic failure\n' >&2
  exit 1
fi
grep -q 'tests/diagnostics.lisp:3:16' "$work_dir/diagnostic-err"
test ! -e "$work_dir/invalid.o"

"$project_root/pslcc" --target=x86_64-none-elf --profile=freestanding \
  -c "$project_root/examples/standalone.lisp" -o "$work_dir/standalone.o"
test -z "$(nm -u "$work_dir/standalone.o")"
"$project_root/pslcc" -O0 --target=x86_64-none-elf \
  --profile=freestanding -c "$project_root/examples/standalone.lisp" \
  -o "$work_dir/standalone-O0.o"
test -z "$(nm -u "$work_dir/standalone-O0.o")"

sbcl --script "$project_root/tests/library.lisp" \
  "$project_root/examples/standalone.lisp" "$work_dir/library.o"
cmp "$work_dir/standalone.o" "$work_dir/library.o"

sh "$project_root/tests/negative.sh"

printf 'PSL smoke test passed\n'
