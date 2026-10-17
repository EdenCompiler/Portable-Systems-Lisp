#!/bin/sh
set -eu
ulimit -c 0
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
target=${1:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
case $target in
  x86_64-windows-gnu) platform=windows ;;
  *) platform=linux ;;
esac
runtime_sources="$project_root/runtime/value.c $project_root/runtime/cons.c $project_root/runtime/string.c $project_root/runtime/symbol.c $project_root/runtime/package.c $project_root/runtime/closure.c $project_root/runtime/vector.c $project_root/runtime/values.c $project_root/runtime/gc.c $project_root/runtime/startup.c"
"$target_cc" -O0 -std=c11 -Wall -Wextra -Werror \
  -c "$project_root/runtime/platform_$platform.c" -o "$work_dir/platform.o"
for level in 0 2; do
  "$target_cc" "-O$level" -std=c11 -Wall -Wextra -Werror \
    "$project_root/tests/harness_bootstrap_value_handles.c" $runtime_sources \
    "$work_dir/platform.o" \
    -o "$work_dir/check$target_suffix"
  run_target "$work_dir/check$target_suffix"
  if run_target "$work_dir/check$target_suffix" stale >"$work_dir/out" 2>"$work_dir/err"; then
    echo "stale managed value handle was accepted ($target, O$level)" >&2
    exit 1
  fi
done
printf 'Managed value handle runtime passed (%s)\n' "$target"
