#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
case $target in x86_64-windows-gnu) platform=windows ;; *) platform=linux ;; esac
# Keep the platform shim at its established MinGW-compatible build level.
"$target_cc" -O0 -std=c11 -Wall -Wextra -Werror -c "$project_root/runtime/platform_$platform.c" -o "$work_dir/platform.o"
for level in 0 1; do
 source=$project_root/tests/bootstrap_native_closures.lisp
 run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$source" "$work_dir/native.o"
 run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$source" "$work_dir/repeat.o"
 cmp "$work_dir/native.o" "$work_dir/repeat.o"
 "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted -c "$source" -o "$work_dir/seed.o"
 for version in native seed; do
  for c_level in 0 2; do
   "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_native_closures.c" "$work_dir/$version.o" "$project_root/runtime/value.c" "$project_root/runtime/cons.c" "$project_root/runtime/string.c" "$project_root/runtime/closure.c" "$project_root/runtime/gc.c" "$project_root/runtime/startup.c" "$work_dir/platform.o" -o "$work_dir/check$target_suffix"
   run_target "$work_dir/check$target_suffix"
  done
 done
 # New source shapes must agree on rejection without publishing an object.
 for bad in \
  '(defun f () (declare (returns value)) (lambda (a b) a))' \
  '(defun f () (declare (returns value)) (lambda () nil))' \
  '(defun f () (declare (returns value)) (function))' \
  '(defun f () (declare (returns value)) (lambda (&rest a) a))' \
  '(defun f () (declare (returns value)) (lambda (&rest) nil))' \
  '(defun f () (declare (returns value)) (lambda (&optional) nil))' \
  '(defun f () (declare (returns value)) (lambda (nil) nil))' \
  '(defun f () (declare (returns value)) (lambda (t) nil))' \
  '(defun f () (declare (returns value)) (lambda (:x) nil))' \
  '(defun f (x) (declare (type s64 x) (returns value)) (lambda (a) (box-fixnum x)))' \
  '(defun f () (declare (returns value)) (function (lambda (a) a) 42))' \
  '(defun f (x) (declare (type value x) (returns value)) (funcall x))' \
  '(defun f (x) (declare (type value x) (returns value)) (funcall x 1 2))' \
  '(defun f () (declare (returns value)) (without-allocation (lambda (a) a)))' \
  '(defun f (x) (declare (type value x) (returns value)) (without-allocation (funcall x 1)))'; do
  printf '%s\n' "$bad" > "$work_dir/invalid.lisp"
  for version in native seed; do
   for repeat in first second; do
    rm -f "$work_dir/rejected.o"
    if [ "$version" = native ]; then
     if run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$work_dir/invalid.lisp" "$work_dir/rejected.o" > "$work_dir/$repeat.error" 2>&1; then
      echo 'Native accepted an invalid closure contract' >&2; exit 1
     else
      status=$?; test "$status" -eq 1
     fi
    else
     if "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted -c "$work_dir/invalid.lisp" -o "$work_dir/rejected.o" > "$work_dir/$repeat.error" 2>&1; then
      echo 'Stage 0 accepted an invalid closure contract' >&2; exit 1
     else
      status=$?; test "$status" -eq 1
     fi
    fi
    test ! -e "$work_dir/rejected.o"
   done
   cmp "$work_dir/first.error" "$work_dir/second.error"
  done
 done
 if run_compiler_host "$compiler" "-O$level" --target="$target" --profile=freestanding "$source" "$work_dir/rejected.o" > "$work_dir/error" 2>&1; then
  echo 'Native accepted hosted closures in freestanding mode' >&2; exit 1
 else
  status=$?; test "$status" -eq 1
 fi
 test ! -e "$work_dir/rejected.o"
 bootstrap_fixture_compile native "$compiler" "$level" "$target" hosted \
  "$project_root/bootstrap/native-core.lisp" "$work_dir/native-core.o"
 bootstrap_fixture_compile native "$compiler" "$level" "$target" hosted \
  "$project_root/bootstrap/host/driver.lisp" "$work_dir/native-host.o"
 bootstrap_fixture_compile seed "$project_root/pslcc" "$level" "$target" hosted \
  "$project_root/bootstrap/native-core.lisp" "$work_dir/seed-core.o"
 bootstrap_fixture_compile seed "$project_root/pslcc" "$level" "$target" hosted \
  "$project_root/bootstrap/host/driver.lisp" "$work_dir/seed-host.o"
 for version in native seed; do
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_closure_ir_api.c" "$work_dir/$version-core.o" "$work_dir/$version-host.o" -o "$work_dir/api$target_suffix"
  run_target "$work_dir/api$target_suffix"
 done
done
printf 'Native lexical closures, arbitrary captures, nested scopes and precise roots passed (%s)\n' "$target"
