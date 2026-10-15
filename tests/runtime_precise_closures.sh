#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
target=${1:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
case $target in x86_64-windows-gnu) platform=windows ;; *) platform=linux ;; esac
"$target_cc" -O0 -std=c11 -Wall -Wextra -Werror -c "$project_root/runtime/platform_$platform.c" -o "$work_dir/platform.o"
for level in 0 2; do
 "$target_cc" "-O$level" -std=c11 -Wall -Wextra -Werror "$project_root/tests/runtime_precise_closures.c" "$project_root/runtime/closure.c" "$project_root/runtime/cons.c" "$project_root/runtime/string.c" "$project_root/runtime/value.c" "$project_root/runtime/gc.c" "$project_root/runtime/startup.c" "$work_dir/platform.o" -o "$work_dir/check$target_suffix"
 run_target "$work_dir/check$target_suffix"
done
printf 'Precise closure construction, invocation and collection passed (%s)\n' "$target"
