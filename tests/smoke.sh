#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

"$project_root/pslcc" -c "$project_root/examples/basic/add.lisp" -o "$work_dir/first.o"
"$project_root/pslcc" -c "$project_root/examples/basic/add.lisp" -o "$work_dir/second.o"
cmp "$work_dir/first.o" "$work_dir/second.o"

readelf -h "$work_dir/first.o" | grep -q 'REL (Relocatable file)'
readelf -r "$work_dir/first.o" | grep -q 'R_X86_64_PLT32'
nm -g "$work_dir/first.o" | grep -q ' T add'
cc "$project_root/examples/basic/harness_add.c" "$work_dir/first.o" -o "$work_dir/harness"
"$work_dir/harness"

for level in 0 1; do
  "$project_root/pslcc" "-O$level" -c \
    "$project_root/examples/abi/void.lisp" \
    -o "$work_dir/abi-void-O$level.o"
  cc "$project_root/examples/abi/harness_void.c" \
    "$work_dir/abi-void-O$level.o" -o "$work_dir/abi-void-O$level"
  "$work_dir/abi-void-O$level"
done

for level in 0 1; do
  "$project_root/pslcc" "-O$level" -c \
    "$project_root/examples/abi/aggregate.lisp" \
    -o "$work_dir/abi-aggregate-O$level.o"
  cc "$project_root/examples/abi/harness_aggregate.c" \
    "$work_dir/abi-aggregate-O$level.o" -o "$work_dir/abi-aggregate-O$level"
  "$work_dir/abi-aggregate-O$level"
done

aggregate_imports=$(nm -u "$work_dir/abi-aggregate-O1.o" |
  awk '{print $2}' | sort)
expected_aggregate_imports=$(printf '%s\n' \
  bump_combined_c bump_mixed_c bump_mixed_reverse_c bump_pair_c \
  bump_tiny_c bump_two_floats_c exhausted_mixed_c exhausted_pair_c | sort)
test "$aggregate_imports" = "$expected_aggregate_imports"

for level in 0 1; do
  "$project_root/pslcc" "-O$level" -c \
    "$project_root/examples/abi/float.lisp" \
    -o "$work_dir/abi-float-O$level.o"
  cc "$project_root/examples/abi/harness_float.c" \
    "$work_dir/abi-float-O$level.o" -o "$work_dir/abi-float-O$level"
  "$work_dir/abi-float-O$level"
done

test "$(nm -u "$work_dir/abi-float-O1.o" | awk '{print $2}' | sort)" = \
  "$(printf 'mix_c\nsum9_c\n' | sort)"

"$project_root/pslcc" "$project_root/examples/basic/program.lisp" \
  -o "$work_dir/psl-program"
"$work_dir/psl-program"

for example in arithmetic recursion macros layout no_allocation; do
  "$project_root/pslcc" -c \
    "$project_root/examples/native/$example.lisp" \
    -o "$work_dir/native-$example.o"
  test -z "$(nm -u "$work_dir/native-$example.o")"
  for level in 0 1; do
    "$project_root/pslcc" "-O$level" \
      "$project_root/examples/native/$example.lisp" \
      -o "$work_dir/native-$example-O$level"
    "$work_dir/native-$example-O$level"
  done
done

for example in immediate list gc_list string_package closure multiple_values; do
  for level in 0 1; do
    "$project_root/pslcc" --profile=hosted "-O$level" \
      "$project_root/examples/hosted/$example.lisp" \
      -o "$work_dir/hosted-$example-O$level"
    "$work_dir/hosted-$example-O$level"
  done
done

test -z "$(nm "$work_dir/native-arithmetic-O1" | grep psl_rt_ || true)"
nm "$work_dir/hosted-immediate-O1" | grep -q ' T psl_rt_eq'
test -z "$(nm "$work_dir/hosted-immediate-O1" | grep ' T psl_rt_collect' || true)"
nm "$work_dir/hosted-list-O1" | grep -q ' T psl_rt_cons'
test -z "$(nm "$work_dir/hosted-list-O1" | grep ' T psl_rt_make_string' || true)"
test -z "$(nm "$work_dir/hosted-list-O1" | grep ' T psl_rt_make_closure' || true)"

"$project_root/pslcc" --profile=hosted --emit=static \
  "$project_root/examples/hosted/list.lisp" -o "$work_dir/libpsl-hosted.a"
ar t "$work_dir/libpsl-hosted.a" | grep -q 'runtime-cons.o'
test -z "$(ar t "$work_dir/libpsl-hosted.a" | grep 'runtime-string.o' || true)"

"$project_root/pslcc" --profile=hosted --emit=shared \
  "$project_root/examples/hosted/string_package.lisp" \
  -o "$work_dir/libpsl-hosted.so"
test -z "$(nm -u "$work_dir/libpsl-hosted.so" | grep psl_rt_ || true)"

"$project_root/pslcc" --profile=hosted -c \
  "$project_root/examples/hosted/closure_module.lisp" \
  -o "$work_dir/closure-module.o"
test -z "$(nm -g "$work_dir/closure-module.o" | grep psl_lambda_ || true)"
"$project_root/pslcc" --profile=hosted --emit=shared \
  --link-input="$work_dir/closure-module.o" \
  "$project_root/examples/hosted/closure.lisp" \
  -o "$work_dir/libpsl-closures.so"
cc "$project_root/tests/harness_closure_module.c" \
  "$work_dir/libpsl-closures.so" -Wl,-rpath,"$work_dir" \
  -o "$work_dir/closure-module-harness"
"$work_dir/closure-module-harness"

"$project_root/pslcc" --profile=hosted --emit=shared \
  --link-input="$work_dir/closure-module.o" \
  "$project_root/examples/native/arithmetic.lisp" \
  -o "$work_dir/libpsl-input-runtime.so"
cc "$project_root/tests/harness_closure_module.c" \
  "$work_dir/libpsl-input-runtime.so" -Wl,-rpath,"$work_dir" \
  -o "$work_dir/input-runtime-harness"
"$work_dir/input-runtime-harness"

"$project_root/pslcc" --emit=static \
  "$project_root/examples/basic/standalone.lisp" -o "$work_dir/libpsl.a"
ar t "$work_dir/libpsl.a" | grep -q 'psl.o'
cc "$project_root/examples/basic/harness_standalone.c" "$work_dir/libpsl.a" \
  -o "$work_dir/static-harness"
"$work_dir/static-harness"
cp "$work_dir/libpsl.a" "$work_dir/libpsl-first.a"
"$project_root/pslcc" --emit=static \
  "$project_root/examples/basic/standalone.lisp" -o "$work_dir/libpsl.a"
cmp "$work_dir/libpsl-first.a" "$work_dir/libpsl.a"

"$project_root/pslcc" --emit=shared \
  "$project_root/examples/basic/standalone.lisp" -o "$work_dir/libpsl.so"
readelf -h "$work_dir/libpsl.so" | grep -q 'DYN (Shared object file)'
cc "$project_root/examples/basic/harness_standalone.c" "$work_dir/libpsl.so" \
  -Wl,-rpath,"$work_dir" -o "$work_dir/shared-harness"
"$work_dir/shared-harness"

"$project_root/pslcc" --emit=shared \
  "$project_root/examples/ffi/shared_data.lisp" \
  -o "$work_dir/libpsl-data.so"
"$project_root/pslcc" --emit=shared \
  "$project_root/examples/ffi/shared_data.lisp" \
  -o "$work_dir/libpsl-data-again.so"
cmp "$work_dir/libpsl-data.so" "$work_dir/libpsl-data-again.so"
readelf -r "$work_dir/libpsl-data.so" | grep -q 'GLOB_DAT'
cc "$project_root/examples/ffi/harness_shared_data.c" \
  "$work_dir/libpsl-data.so" -Wl,-rpath,"$work_dir" \
  -o "$work_dir/shared-data-harness"
"$work_dir/shared-data-harness"

"$project_root/pslcc" --emit=shared \
  "$project_root/examples/ffi/source_import.lisp" \
  -o "$work_dir/libpsl-ffi.so"
cc "$project_root/examples/ffi/harness_source_import.c" \
  "$work_dir/libpsl-ffi.so" -Wl,-rpath,"$work_dir" \
  -o "$work_dir/shared-ffi-harness"
"$work_dir/shared-ffi-harness"

cc -c "$project_root/examples/abi/harness_stack.c" \
  -o "$work_dir/abi-stack-c.o"
"$project_root/pslcc" --link-input="$work_dir/abi-stack-c.o" \
  "$project_root/examples/abi/stack.lisp" -o "$work_dir/linked-abi-stack"
"$work_dir/linked-abi-stack"

for level in 0 1; do
  "$project_root/pslcc" "-O$level" -c \
    "$project_root/examples/ffi/data_import.lisp" \
    -o "$work_dir/ffi-data-O$level.o"
  readelf -r "$work_dir/ffi-data-O$level.o" | grep -q 'R_X86_64_GOTPCREL'
  cc "$project_root/examples/ffi/harness_data_import.c" \
    "$work_dir/ffi-data-O$level.o" -o "$work_dir/ffi-data-O$level"
  "$work_dir/ffi-data-O$level"
done

test "$(nm -u "$work_dir/ffi-data-O1.o" | awk '{print $2}')" = c_counter
nm -g "$work_dir/ffi-data-O1.o" | grep -q ' D psl_counter'
"$project_root/pslcc" -c "$project_root/examples/ffi/data_import.lisp" \
  -o "$work_dir/ffi-data-repeat.o"
cmp "$work_dir/ffi-data-O1.o" "$work_dir/ffi-data-repeat.o"

"$project_root/pslcc" -c "$project_root/examples/ffi/data_only.lisp" \
  -o "$work_dir/data-only.o"
nm -g "$work_dir/data-only.o" | grep -q ' D psl_only'
test -z "$(nm -u "$work_dir/data-only.o")"
cc "$project_root/examples/ffi/harness_data_only.c" \
  "$work_dir/data-only.o" -o "$work_dir/data-only-harness"
"$work_dir/data-only-harness"

for level in 0 1; do
  "$project_root/pslcc" "-O$level" -c \
    "$project_root/examples/abi/stack.lisp" \
    -o "$work_dir/abi-stack-O$level.o"
  cc "$project_root/examples/abi/harness_stack.c" \
    "$work_dir/abi-stack-O$level.o" -o "$work_dir/abi-stack-O$level"
  "$work_dir/abi-stack-O$level"
done

for level in 0 1; do
  "$project_root/pslcc" "-O$level" -c \
    "$project_root/examples/abi/layout.lisp" \
    -o "$work_dir/c-layout-O$level.o"
  cc "$project_root/examples/abi/harness_layout.c" \
    "$work_dir/c-layout-O$level.o" -o "$work_dir/c-layout-O$level"
  "$work_dir/c-layout-O$level"
done

"$project_root/pslcc" -O0 -c "$project_root/examples/basic/add.lisp" \
  -o "$work_dir/add-O0.o"
cc "$project_root/examples/basic/harness_add.c" "$work_dir/add-O0.o" \
  -o "$work_dir/add-O0-harness"
"$work_dir/add-O0-harness"

"$project_root/pslcc" -c "$project_root/examples/memory/memory.lisp" \
  -o "$work_dir/memory.o"
cc "$project_root/examples/memory/harness_memory.c" "$work_dir/memory.o" \
  -o "$work_dir/memory-harness"
"$work_dir/memory-harness"
test -z "$(nm -u "$work_dir/memory.o")"

"$project_root/pslcc" -O0 -c "$project_root/examples/memory/memory.lisp" \
  -o "$work_dir/memory-O0.o"
cc "$project_root/examples/memory/harness_memory.c" "$work_dir/memory-O0.o" \
  -o "$work_dir/memory-O0-harness"
"$work_dir/memory-O0-harness"

"$project_root/pslcc" -c "$project_root/examples/ffi/source_import.lisp" \
  -o "$work_dir/ffi-source.o"
"$project_root/pslcc" -c "$project_root/examples/ffi/source_import.lisp" \
  -o "$work_dir/ffi-source-again.o"
cmp "$work_dir/ffi-source.o" "$work_dir/ffi-source-again.o"
test -z "$(nm -u "$work_dir/ffi-source.o")"
cc "$project_root/examples/ffi/harness_source_import.c" "$work_dir/ffi-source.o" \
  -o "$work_dir/ffi-source-harness"
"$work_dir/ffi-source-harness"

"$project_root/pslcc" -O0 -c "$project_root/examples/ffi/source_import.lisp" \
  -o "$work_dir/ffi-source-O0.o"
cc "$project_root/examples/ffi/harness_source_import.c" \
  "$work_dir/ffi-source-O0.o" -o "$work_dir/ffi-source-O0-harness"
"$work_dir/ffi-source-O0-harness"

for level in 0 1; do
  "$project_root/pslcc" "-O$level" -c \
    "$project_root/examples/optimization/optimizer.lisp" \
    -o "$work_dir/optimizer-O$level.o"
  cc "$project_root/examples/optimization/harness_optimizer.c" \
    "$work_dir/optimizer-O$level.o" \
    -o "$work_dir/optimizer-O$level"
  "$work_dir/optimizer-O$level"
  "$project_root/pslcc" "-O$level" --dump-ir=lir -c \
    "$project_root/examples/optimization/optimizer.lisp" -o "$work_dir/dump-O$level.o" \
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
  "$project_root/examples/optimization/optimizer.lisp" -o "$work_dir/all-dumps.o" \
  >"$work_dir/all-dumps.txt"
grep -q '^HIR constant_wrap ' "$work_dir/all-dumps.txt"
grep -q '^SSA constant_wrap ' "$work_dir/all-dumps.txt"
grep -q '^LIR constant_wrap ' "$work_dir/all-dumps.txt"
awk '/^SSA constant_wrap / { in_function=1; next }
     /^SSA / { in_function=0 }
     in_function && /CONSTANT :U8 value=4/ { found=1 }
     END { exit !found }' "$work_dir/all-dumps.txt"
"$project_root/pslcc" -O0 --dump-ir=ssa -c \
  "$project_root/examples/basic/add.lisp" -o "$work_dir/ssa-joins.o" \
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
  -c "$project_root/examples/basic/standalone.lisp" -o "$work_dir/standalone.o"
test -z "$(nm -u "$work_dir/standalone.o")"
"$project_root/pslcc" -O0 --target=x86_64-none-elf \
  --profile=freestanding -c "$project_root/examples/basic/standalone.lisp" \
  -o "$work_dir/standalone-O0.o"
test -z "$(nm -u "$work_dir/standalone-O0.o")"

sbcl --script "$project_root/tests/library.lisp" \
  "$project_root/examples/basic/standalone.lisp" "$work_dir/library.o"
cmp "$work_dir/standalone.o" "$work_dir/library.o"

sh "$project_root/tests/negative.sh"
sh "$project_root/tests/runtime.sh"

printf 'PSL smoke test passed\n'
