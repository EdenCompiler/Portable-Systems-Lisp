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
 x86_64-windows-gnu) platform=windows; nm_tool=x86_64-w64-mingw32-nm; cold_flags= ;;
 x86_64-linux-gnu) platform=linux; nm_tool=nm; cold_flags='-DVERIFY_MALLOC -Wl,--wrap,malloc' ;;
 aarch64-linux-gnu) platform=linux; nm_tool=aarch64-linux-gnu-nm; cold_flags='-DVERIFY_MALLOC -Wl,--wrap,malloc' ;;
 riscv64-linux-gnu) platform=linux; nm_tool=riscv64-linux-gnu-nm; cold_flags='-DVERIFY_MALLOC -Wl,--wrap,malloc' ;;
esac
"$target_cc" -O0 -Wall -Wextra -Werror -c "$project_root/runtime/platform_$platform.c" -o "$work_dir/platform.o"
"$target_cc" -O2 -std=c11 -Wall -Wextra -Werror "$project_root/tests/runtime_cold_values.c" "$project_root/runtime/values.c" "$project_root/runtime/gc.c" "$project_root/runtime/startup.c" "$work_dir/platform.o" -Wl,--wrap,psl_rt_register_permanent_roots $cold_flags -o "$work_dir/cold$target_suffix"
run_target "$work_dir/cold$target_suffix"
# No emulated TLS calls may hide allocation in the Windows getter path.
"$target_cc" -O2 -std=c11 -Wall -Wextra -Werror -c "$project_root/runtime/values.c" -o "$work_dir/values.o"
test -z "$("$nm_tool" -u "$work_dir/values.o" | grep __emutls || true)"
for level in 0 1; do
 source=$project_root/tests/bootstrap_multiple_values.lisp
 run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$source" "$work_dir/native.o"
 run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$source" "$work_dir/repeat.o"
 cmp "$work_dir/native.o" "$work_dir/repeat.o"
 "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted -c "$source" -o "$work_dir/seed.o"
 for version in native seed; do
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_multiple_values.c" "$work_dir/$version.o" "$project_root/runtime/value.c" "$project_root/runtime/cons.c" "$project_root/runtime/string.c" "$project_root/runtime/values.c" "$project_root/runtime/gc.c" "$project_root/runtime/startup.c" "$work_dir/platform.o" -o "$work_dir/check$target_suffix"
  run_target "$work_dir/check$target_suffix"
 done
 run_compiler_host "$compiler" "-O$level" --target="$target" "$project_root/bootstrap/native-core.lisp" "$work_dir/native-core.o"
 run_compiler_host "$compiler" "-O$level" --target="$target" "$project_root/bootstrap/host/driver.lisp" "$work_dir/native-host.o"
 "$project_root/pslcc" "-O$level" --target="$target" -c "$project_root/bootstrap/native-core.lisp" -o "$work_dir/seed-core.o"
 "$project_root/pslcc" "-O$level" --target="$target" -c "$project_root/bootstrap/host/driver.lisp" -o "$work_dir/seed-host.o"
 for version in native seed; do
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_multiple_values_api.c" "$work_dir/$version-core.o" "$work_dir/$version-host.o" -o "$work_dir/api$target_suffix"
  run_target "$work_dir/api$target_suffix"
 done
 # Both frontends reject constant binding names rather than shadowing them.
 for names in '(nil b)' '(t b)' '(:a b)'; do
  printf '(defun f () (declare (returns value)) (multiple-value-bind %s (values 1 2) b))\n' "$names" > "$work_dir/invalid.lisp"
  if "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted -c "$work_dir/invalid.lisp" -o "$work_dir/rejected.o" > "$work_dir/error" 2>&1; then
   echo 'Stage 0 accepted constant multiple-value binding name' >&2; exit 1
  fi
  test ! -e "$work_dir/rejected.o"
 done
done
printf 'Native two-value subset passed (%s)\n' "$target"
