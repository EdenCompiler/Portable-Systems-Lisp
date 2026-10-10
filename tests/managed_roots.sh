#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
target=${1:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
case $target in
 x86_64-windows-gnu) platform=windows; threads=; target_nm=x86_64-w64-mingw32-nm ;;
 x86_64-linux-gnu) platform=linux; threads=-pthread; target_nm=nm ;;
 aarch64-linux-gnu) platform=linux; threads=-pthread; target_nm=aarch64-linux-gnu-nm ;;
 riscv64-linux-gnu) platform=linux; threads=-pthread; target_nm=riscv64-linux-gnu-nm ;;
esac
cat "$project_root/tests/managed_roots.lisp" > "$work_dir/source.lisp"
{
 echo '(ffi:import-function "root_large_check" ((first value) (last value)) -> void)'
 echo '(defun root_large () (declare (returns value) (c-export :c)) (let ('
 awk 'BEGIN { for(i=0;i<96;i++) printf "(v%d (ffi:call root_cons (box-fixnum %d) nil))\n",i,i }'
 echo ') (ffi:call root_large_check v0 v95) v95))'
} >> "$work_dir/source.lisp"
"$target_cc" -O0 -Wall -Wextra -Werror $threads -c \
 "$project_root/runtime/platform_$platform.c" -o "$work_dir/platform.o"
"$target_cc" -O2 -Wall -Wextra -Werror $threads -c \
 "$project_root/tests/managed_roots.c" -o "$work_dir/harness.o"
for level in 0 1; do
 "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted -c \
   --dump-ir=lir "$work_dir/source.lisp" -o "$work_dir/roots.o" > "$work_dir/lir.txt"
 "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted -c \
   "$work_dir/source.lisp" -o "$work_dir/repeat.o"
 cmp "$work_dir/roots.o" "$work_dir/repeat.o"
 grep -q 'ROOTS-INIT' "$work_dir/lir.txt"
 "$target_nm" -u "$work_dir/roots.o" | grep -q 'psl_rt_push_roots'
 "$target_nm" -u "$work_dir/roots.o" | grep -q 'psl_rt_pop_roots'
 "$target_cc" -O2 -Wall -Wextra -Werror $threads \
  "$work_dir/harness.o" "$work_dir/roots.o" "$project_root/runtime/value.c" \
  "$project_root/runtime/cons.c" "$project_root/runtime/gc.c" \
  "$project_root/runtime/startup.c" "$work_dir/platform.o" \
  -o "$work_dir/check$target_suffix"
 run_target "$work_dir/check$target_suffix"
 # The compilation API must select GC for compiler-inserted root operations.
 "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted \
   --link-input="$work_dir/harness.o" "$work_dir/source.lisp" \
   -o "$work_dir/linked$target_suffix"
 run_target "$work_dir/linked$target_suffix"
done
if [ "$target" = x86_64-linux-gnu ]; then
 sbcl --script "$project_root/tests/managed_roots_verifier.lisp"
fi
printf 'Managed compiler roots passed (%s)\n' "$target"
