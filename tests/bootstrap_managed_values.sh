#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
case $target in
 x86_64-windows-gnu) platform=windows; nm_tool=x86_64-w64-mingw32-nm ;;
 x86_64-linux-gnu) platform=linux; nm_tool=nm ;;
 aarch64-linux-gnu) platform=linux; nm_tool=aarch64-linux-gnu-nm ;;
 riscv64-linux-gnu) platform=linux; nm_tool=riscv64-linux-gnu-nm ;;
esac
"$target_cc" -O0 -Wall -Wextra -Werror -c \
 "$project_root/runtime/platform_$platform.c" -o "$work_dir/platform.o"
source=$project_root/tests/bootstrap_managed_values.lisp
for level in 0 1; do
 run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$source" "$work_dir/native.o"
 run_compiler_host "$compiler" --profile=hosted --target="$target" "-O$level" "$source" "$work_dir/repeat.o"
 cmp "$work_dir/native.o" "$work_dir/repeat.o"
 "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted -c "$source" -o "$work_dir/seed.o"
 for version in native seed; do
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
   "$project_root/tests/harness_bootstrap_managed_values.c" "$work_dir/$version.o" \
   "$project_root/runtime/value.c" "$project_root/runtime/cons.c" \
   "$project_root/runtime/gc.c" "$project_root/runtime/startup.c" "$work_dir/platform.o" \
   -o "$work_dir/check$target_suffix"
  run_target "$work_dir/check$target_suffix"
 done
 # Run the receiver and compilation API through both source implementations.
 run_compiler_host "$compiler" "-O$level" --target="$target" \
  "$project_root/bootstrap/native-core.lisp" "$work_dir/native-core.o"
 run_compiler_host "$compiler" "-O$level" --target="$target" \
  "$project_root/bootstrap/host/driver.lisp" "$work_dir/native-host.o"
 "$project_root/pslcc" "-O$level" --target="$target" -c \
  "$project_root/bootstrap/native-core.lisp" -o "$work_dir/seed-core.o"
 "$project_root/pslcc" "-O$level" --target="$target" -c \
  "$project_root/bootstrap/host/driver.lisp" -o "$work_dir/seed-host.o"
 for version in native seed; do
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
   "$project_root/tests/harness_bootstrap_managed_api.c" "$work_dir/$version-core.o" \
   "$work_dir/$version-host.o" -o "$work_dir/api$target_suffix"
  run_target "$work_dir/api$target_suffix"
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
   "$project_root/tests/harness_bootstrap_runtime_signatures.c" "$work_dir/$version-core.o" \
   -o "$work_dir/signatures$target_suffix"
  run_target "$work_dir/signatures$target_suffix"
 done
 # Hosted immediates alone introduce no runtime symbols.
 printf '%s\n' '(defun leaf (x) (declare (type value x) (returns value) (c-export :c)) x)' > "$work_dir/leaf.lisp"
 run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted \
  "$work_dir/leaf.lisp" "$work_dir/leaf.o"
 test -z "$("$nm_tool" -u "$work_dir/leaf.o")"
 for profile in default freestanding; do
  if test "$profile" = default; then
   if run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$work_dir/rejected.o" > "$work_dir/error" 2>&1; then
    echo 'Managed source accepted in default native profile' >&2; exit 1
   fi
  elif run_compiler_host "$compiler" "-O$level" --target="$target" --profile=freestanding "$source" "$work_dir/rejected.o" > "$work_dir/error" 2>&1; then
   echo 'Managed source accepted in freestanding native profile' >&2; exit 1
  fi
  test ! -e "$work_dir/rejected.o"
 done
 printf '%s\n' '(defun unsafe () (declare (returns value)) (without-allocation (cons 1 nil)))' > "$work_dir/unsafe.lisp"
 if run_compiler_host "$compiler" "-O$level" --profile=hosted --target="$target" "$work_dir/unsafe.lisp" "$work_dir/rejected.o" > "$work_dir/error" 2>&1; then
  echo 'Allocating region accepted' >&2; exit 1
 fi
 grep -q 'WITHOUT-ALLOCATION cannot certify call to psl_rt_cons_precise' "$work_dir/error"
 test ! -e "$work_dir/rejected.o"
done
for option in '--profile=unknown' '--profile=hosted-extra' '--profile='; do
 if run_compiler_host "$compiler" "$option" "$source" "$work_dir/rejected.o" > "$work_dir/error" 2>&1; then
  echo 'Invalid native profile accepted' >&2; exit 1
 fi
 test ! -e "$work_dir/rejected.o"
done
for repeated in '-O0' '--profile=hosted' '--target=x86_64-linux-gnu'; do
 if run_compiler_host "$compiler" "$repeated" "$repeated" "$source" "$work_dir/rejected.o" > "$work_dir/error" 2>&1; then
  echo 'Duplicate native option accepted' >&2; exit 1
 fi
 test ! -e "$work_dir/rejected.o"
done
printf 'Native managed values and safety checks passed (%s)\n' "$target"
