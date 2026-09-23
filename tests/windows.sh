#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

for tool in x86_64-w64-mingw32-gcc x86_64-w64-mingw32-ar \
            x86_64-w64-mingw32-nm x86_64-w64-mingw32-objdump wine; do
  command -v "$tool" >/dev/null
done

run_windows() {
  WINEDEBUG=-all wine "$1"
}

for level in 0 1; do
  for example in arithmetic recursion macros layout no_allocation; do
    "$project_root/pslcc" --target=x86_64-windows-gnu "-O$level" \
      "$project_root/examples/native/$example.lisp" \
      -o "$work_dir/native-$example-O$level.exe"
    run_windows "$work_dir/native-$example-O$level.exe"
  done

  for example in stack float aggregate layout void windows_odd_aggregate; do
    "$project_root/pslcc" -c --target=x86_64-windows-gnu "-O$level" \
      "$project_root/examples/abi/$example.lisp" \
      -o "$work_dir/abi-$example-O$level.o"
    x86_64-w64-mingw32-gcc \
      "$project_root/examples/abi/harness_$example.c" \
      "$work_dir/abi-$example-O$level.o" \
      -o "$work_dir/abi-$example-O$level.exe"
    run_windows "$work_dir/abi-$example-O$level.exe"
  done

  for example in immediate list gc_list string_package closure multiple_values; do
    "$project_root/pslcc" --target=x86_64-windows-gnu \
      --profile=hosted "-O$level" \
      "$project_root/examples/hosted/$example.lisp" \
      -o "$work_dir/hosted-$example-O$level.exe"
    run_windows "$work_dir/hosted-$example-O$level.exe"
  done
done

x86_64-w64-mingw32-objdump -f "$work_dir/abi-aggregate-O0.o" | \
  grep -q 'file format pe-x86-64'
x86_64-w64-mingw32-objdump -r "$work_dir/abi-aggregate-O0.o" | \
  grep -q 'IMAGE_REL_AMD64_REL32'
x86_64-w64-mingw32-objdump -r "$work_dir/abi-aggregate-O0.o" | \
  grep -q 'IMAGE_REL_AMD64_ADDR32NB'
x86_64-w64-mingw32-objdump -h "$work_dir/abi-aggregate-O0.o" | \
  grep -q '\.xdata'

cat >"$work_dir/oversized.lisp" <<'SOURCE'
(defcstruct too-large (a u64) (b u64) (c u64))
(defun invalid (value)
  (declare (type too-large value) (returns too-large) (c-export :c))
  value)
SOURCE
if "$project_root/pslcc" -c --target=x86_64-windows-gnu \
    "$work_dir/oversized.lisp" -o "$work_dir/oversized.o" \
    >"$work_dir/oversized-out" 2>"$work_dir/oversized-err"; then
  echo 'Expected oversized Windows C aggregate to fail' >&2
  exit 1
fi
grep -q 'scalar C layout of at most 16 bytes' "$work_dir/oversized-err"
test ! -e "$work_dir/oversized.o"

for example in data_import source_import data_only; do
  "$project_root/pslcc" -c --target=x86_64-windows-gnu \
    "$project_root/examples/ffi/$example.lisp" \
    -o "$work_dir/ffi-$example.o"
  x86_64-w64-mingw32-gcc \
    "$project_root/examples/ffi/harness_$example.c" \
    "$work_dir/ffi-$example.o" \
    -o "$work_dir/ffi-$example.exe"
  run_windows "$work_dir/ffi-$example.exe"
done

"$project_root/pslcc" --target=x86_64-windows-gnu --emit=static \
  "$project_root/examples/basic/standalone.lisp" \
  -o "$work_dir/libpsl.a"
x86_64-w64-mingw32-gcc "$project_root/examples/basic/harness_standalone.c" \
  "$work_dir/libpsl.a" -o "$work_dir/static.exe"
run_windows "$work_dir/static.exe"
x86_64-w64-mingw32-gcc -c "$project_root/tests/windows_function_provider.c" \
  -o "$work_dir/provider.obj"
"$project_root/pslcc" --target=x86_64-windows-gnu --emit=static \
  --link-input="$work_dir/provider.obj" \
  "$project_root/examples/basic/standalone.lisp" \
  -o "$work_dir/libpsl-obj.a"
x86_64-w64-mingw32-gcc "$project_root/examples/basic/harness_standalone.c" \
  "$work_dir/libpsl-obj.a" -o "$work_dir/static-obj.exe"
run_windows "$work_dir/static-obj.exe"
x86_64-w64-mingw32-gcc "$project_root/tests/harness_windows_unwind.c" \
  "$work_dir/libpsl.a" -o "$work_dir/unwind.exe"
run_windows "$work_dir/unwind.exe"

"$project_root/pslcc" --target=x86_64-windows-gnu --profile=hosted \
  --emit=static "$project_root/examples/hosted/closure_module.lisp" \
  -o "$work_dir/libpsl-hosted.a"
x86_64-w64-mingw32-gcc "$project_root/tests/harness_closure_module.c" \
  "$work_dir/libpsl-hosted.a" -o "$work_dir/hosted-static.exe"
run_windows "$work_dir/hosted-static.exe"

"$project_root/pslcc" --target=x86_64-windows-gnu --emit=shared \
  "$project_root/examples/basic/standalone.lisp" \
  -o "$work_dir/psl.dll"
x86_64-w64-mingw32-gcc "$project_root/examples/basic/harness_standalone.c" \
  "$work_dir/psl.dll" -o "$work_dir/shared.exe"
run_windows "$work_dir/shared.exe"

"$project_root/pslcc" --target=x86_64-windows-gnu --emit=shared \
  "$project_root/examples/ffi/shared_data.lisp" \
  -o "$work_dir/psl_data.dll"
x86_64-w64-mingw32-gcc "$project_root/examples/ffi/harness_shared_data.c" \
  "$work_dir/psl_data.dll" -o "$work_dir/shared_data.exe"
run_windows "$work_dir/shared_data.exe"

x86_64-w64-mingw32-gcc -shared \
  "$project_root/examples/ffi/data_provider.c" \
  "-Wl,--out-implib,$work_dir/libprovider.dll.a" \
  -o "$work_dir/provider.dll"
"$project_root/pslcc" --target=x86_64-windows-gnu --emit=shared \
  --link-input="$work_dir/libprovider.dll.a" \
  "$project_root/examples/ffi/data_import.lisp" \
  -o "$work_dir/consumer.dll"
x86_64-w64-mingw32-gcc "$project_root/tests/harness_windows_import_dll.c" \
  "$work_dir/consumer.dll" "$work_dir/provider.dll" \
  -o "$work_dir/import_dll.exe"
run_windows "$work_dir/import_dll.exe"

x86_64-w64-mingw32-gcc -shared \
  "$project_root/tests/windows_function_provider.c" \
  "-Wl,--out-implib,$work_dir/libfunction.dll.a" \
  -o "$work_dir/function.dll"
"$project_root/pslcc" --target=x86_64-windows-gnu --emit=shared \
  --link-input="$work_dir/libfunction.dll.a" \
  "$project_root/examples/basic/add.lisp" \
  -o "$work_dir/function_consumer.dll"
x86_64-w64-mingw32-gcc \
  "$project_root/tests/harness_windows_import_function.c" \
  "$work_dir/function_consumer.dll" -o "$work_dir/import_function.exe"
run_windows "$work_dir/import_function.exe"

"$project_root/pslcc" -c --target=x86_64-windows-gnu --profile=hosted \
  "$project_root/examples/hosted/closure_module.lisp" \
  -o "$work_dir/closure_module.o"
"$project_root/pslcc" --target=x86_64-windows-gnu --emit=shared \
  --link-input="$work_dir/closure_module.o" \
  "$project_root/examples/basic/standalone.lisp" \
  -o "$work_dir/psl_combined.dll"
x86_64-w64-mingw32-gcc "$project_root/tests/harness_windows_link_input.c" \
  "$work_dir/psl_combined.dll" -o "$work_dir/combined.exe"
run_windows "$work_dir/combined.exe"

test -z "$(x86_64-w64-mingw32-nm "$work_dir/native-arithmetic-O1.exe" | \
            grep psl_rt_ || true)"
test -z "$(x86_64-w64-mingw32-nm "$work_dir/hosted-immediate-O1.exe" | \
            grep ' T psl_rt_collect' || true)"
x86_64-w64-mingw32-nm "$work_dir/hosted-list-O1.exe" | \
  grep -q ' T psl_rt_collect'

set -- "$project_root/tests/runtime.c"
for source in "$project_root"/runtime/*.c; do
  if [ "${source##*/}" != platform_linux.c ]; then
    set -- "$@" "$source"
  fi
done
x86_64-w64-mingw32-gcc -std=c11 -Wall -Wextra -Werror -O0 \
  "$@" -o "$work_dir/runtime.exe"
run_windows "$work_dir/runtime.exe"

mkdir "$work_dir/repeat-a" "$work_dir/repeat-b"
for directory in repeat-a repeat-b; do
  "$project_root/pslcc" -c --target=x86_64-windows-gnu \
    "$project_root/examples/basic/standalone.lisp" \
    -o "$work_dir/$directory/psl.o"
  "$project_root/pslcc" --target=x86_64-windows-gnu --emit=static \
    "$project_root/examples/basic/standalone.lisp" \
    -o "$work_dir/$directory/psl.a"
  "$project_root/pslcc" --target=x86_64-windows-gnu --emit=shared \
    "$project_root/examples/basic/standalone.lisp" \
    -o "$work_dir/$directory/psl.dll"
  "$project_root/pslcc" --target=x86_64-windows-gnu \
    "$project_root/examples/native/arithmetic.lisp" \
    -o "$work_dir/$directory/psl.exe"
done
for extension in o a dll exe; do
  cmp "$work_dir/repeat-a/psl.$extension" \
      "$work_dir/repeat-b/psl.$extension"
done

echo 'PSL Windows test passed'
