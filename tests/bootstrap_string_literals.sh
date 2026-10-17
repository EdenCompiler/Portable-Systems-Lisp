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
cat "$project_root/tests/bootstrap_string_literals.lisp" > "$work_dir/strings.lisp"
printf '(defun sl_zero () (declare (returns value) (c-export :c)) "a\000b")\n' >> "$work_dir/strings.lisp"
printf '(defun sl_large () (declare (returns value) (c-export :c)) "' >> "$work_dir/strings.lisp"
awk 'BEGIN { for(i=0;i<10000;i++) printf "%c",65+i%26 }' >> "$work_dir/strings.lisp"
printf '")\n' >> "$work_dir/strings.lisp"
"$target_cc" -O0 -Wall -Wextra -Werror -c "$project_root/runtime/platform_$platform.c" -o "$work_dir/platform.o"
for level in 0 1; do
 run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$work_dir/strings.lisp" "$work_dir/native.o"
 run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$work_dir/strings.lisp" "$work_dir/repeat.o"
 cmp "$work_dir/native.o" "$work_dir/repeat.o"
 "$nm_tool" -u "$work_dir/native.o" | grep -q psl_rt_make_string_from_bytes_precise
 "$nm_tool" -u "$work_dir/native.o" | grep -q psl_rt_push_roots
 "$nm_tool" -u "$work_dir/native.o" | grep -q psl_rt_pop_roots
 # Literal bytes must remain private data symbols.
 test "$("$nm_tool" -g --defined-only "$work_dir/native.o" | wc -l)" -eq 10
 "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted -c "$work_dir/strings.lisp" -o "$work_dir/seed.o"
 for version in native seed; do
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_string_literals.c" "$work_dir/$version.o" "$project_root/runtime/value.c" "$project_root/runtime/cons.c" "$project_root/runtime/string.c" "$project_root/runtime/gc.c" "$project_root/runtime/startup.c" "$work_dir/platform.o" -o "$work_dir/check$target_suffix"
  run_target "$work_dir/check$target_suffix"
 done
 # Stage 0's automatic runtime selection must include the byte-copy entry.
 "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror -c "$project_root/tests/harness_bootstrap_string_literals.c" -o "$work_dir/link.o"
 "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted --link-input="$work_dir/link.o" "$work_dir/strings.lisp" -o "$work_dir/linked$target_suffix"
 run_target "$work_dir/linked$target_suffix"
 bootstrap_fixture_compile native "$compiler" "$level" "$target" hosted \
  "$project_root/bootstrap/native-core.lisp" "$work_dir/native-core.o"
 bootstrap_fixture_compile native "$compiler" "$level" "$target" hosted \
  "$project_root/bootstrap/host/driver.lisp" "$work_dir/native-host.o"
 bootstrap_fixture_compile seed "$project_root/pslcc" "$level" "$target" hosted \
  "$project_root/bootstrap/native-core.lisp" "$work_dir/seed-core.o"
 bootstrap_fixture_compile seed "$project_root/pslcc" "$level" "$target" hosted \
  "$project_root/bootstrap/host/driver.lisp" "$work_dir/seed-host.o"
 for version in native seed; do
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_string_literals_api.c" "$work_dir/$version-core.o" "$work_dir/$version-host.o" -o "$work_dir/api$target_suffix"
  run_target "$work_dir/api$target_suffix"
 done
done
printf 'Native string literals passed (%s)\n' "$target"
