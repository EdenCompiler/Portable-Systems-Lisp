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
"$target_cc" -O0 -Wall -Wextra -Werror -c "$project_root/runtime/platform_$platform.c" -o "$work_dir/platform.o"
"$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
 "$project_root/tests/runtime_precise_string.c" "$project_root/runtime/value.c" \
 "$project_root/runtime/string.c" "$project_root/runtime/gc.c" \
 "$project_root/runtime/startup.c" "$work_dir/platform.o" -o "$work_dir/runtime$target_suffix"
run_target "$work_dir/runtime$target_suffix"
# The linker registry must recognize the explicit precise constructor import.
cat > "$work_dir/link.lisp" <<'LISP'
(ffi:import-function "psl_rt_make_string_precise" ((n usize) (fill u8)) -> value)
(defun byte_link () (declare (returns value) (c-export :c))
 (ffi:call psl_rt_make_string_precise 3 255))
LISP
printf '#include "%s/runtime/psl_runtime.h"\n' "$project_root" > "$work_dir/link.c"
cat >> "$work_dir/link.c" <<'C'
#include <assert.h>
extern psl_value byte_link(void);
int main(void) {
 psl_value s=byte_link();assert(psl_rt_string_length(s)==3);
 assert(psl_rt_string_byte(s,2)==255);
 psl_rt_collect_precise();assert(!psl_rt_live_objects());return 0;
}
C
"$target_cc" -O2 -std=c11 -Wall -Wextra -Werror -c "$work_dir/link.c" -o "$work_dir/link.o"
"$project_root/pslcc" -O1 --target="$target" --profile=hosted \
 --link-input="$work_dir/link.o" "$work_dir/link.lisp" -o "$work_dir/linked$target_suffix"
run_target "$work_dir/linked$target_suffix"
for level in 0 1; do
 source=$project_root/tests/bootstrap_byte_strings.lisp
 run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$source" "$work_dir/native.o"
 run_compiler_host "$compiler" "-O$level" --profile=hosted --target="$target" "$source" "$work_dir/repeat.o"
 cmp "$work_dir/native.o" "$work_dir/repeat.o"
 "$nm_tool" -u "$work_dir/native.o" | grep -q psl_rt_push_roots
 "$nm_tool" -u "$work_dir/native.o" | grep -q psl_rt_pop_roots
 "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted -c "$source" -o "$work_dir/seed.o"
 for version in native seed; do
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_byte_strings.c" "$work_dir/$version.o" "$project_root/runtime/value.c" "$project_root/runtime/cons.c" "$project_root/runtime/string.c" "$project_root/runtime/gc.c" "$project_root/runtime/startup.c" "$work_dir/platform.o" -o "$work_dir/check$target_suffix"
  run_target "$work_dir/check$target_suffix"
 done
 bootstrap_fixture_compile native "$compiler" "$level" "$target" freestanding \
  "$project_root/bootstrap/native-core.lisp" "$work_dir/native-core.o"
 bootstrap_fixture_compile native "$compiler" "$level" "$target" freestanding \
  "$project_root/bootstrap/host/driver.lisp" "$work_dir/native-host.o"
 bootstrap_fixture_compile seed "$project_root/pslcc" "$level" "$target" freestanding \
  "$project_root/bootstrap/native-core.lisp" "$work_dir/seed-core.o"
 bootstrap_fixture_compile seed "$project_root/pslcc" "$level" "$target" freestanding \
  "$project_root/bootstrap/host/driver.lisp" "$work_dir/seed-host.o"
 for version in native seed; do
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_byte_strings_api.c" "$work_dir/$version-core.o" "$work_dir/$version-host.o" -o "$work_dir/api$target_suffix"
  run_target "$work_dir/api$target_suffix"
 done
done
printf 'Native byte strings passed (%s)\n' "$target"
