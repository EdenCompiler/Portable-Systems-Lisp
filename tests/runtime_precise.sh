#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
target=${1:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
case $target in
  x86_64-windows-gnu) platform=windows; thread_flags= ;;
  *) platform=linux; thread_flags=-pthread ;;
esac
# The OS adapter uses the runtime's existing baseline compilation. In particular,
# GCC's optimized MinGW intrinsic reports a system-header array-bounds warning.
"$target_cc" -O0 -std=c11 -Wall -Wextra -Werror $thread_flags -c \
  "$project_root/runtime/platform_$platform.c" -o "$work_dir/platform.o"
for level in 0 2; do
  "$target_cc" "-O$level" -std=c11 -Wall -Wextra -Werror $thread_flags \
    "$project_root/tests/runtime_precise.c" "$project_root/runtime/value.c" \
    "$project_root/runtime/cons.c" "$project_root/runtime/gc.c" \
    "$project_root/runtime/startup.c" "$work_dir/platform.o" \
    -o "$work_dir/check$target_suffix"
  run_target "$work_dir/check$target_suffix"
done
# Imported precise-runtime symbols in a link input select their existing modules.
"$target_cc" -O2 -std=c11 -Wall -Wextra -Werror -DPSL_RUNTIME_LINK_PROBE -c \
  "$project_root/tests/runtime_precise.c" -o "$work_dir/probe.o"
for level in 0 1; do
  "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted \
    --link-input="$work_dir/probe.o" "$project_root/examples/basic/standalone.lisp" \
    -o "$work_dir/linked-O$level$target_suffix"
  run_target "$work_dir/linked-O$level$target_suffix"
done
