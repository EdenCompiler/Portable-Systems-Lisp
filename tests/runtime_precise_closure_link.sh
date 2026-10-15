#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
target=${1:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
for level in 0 1; do
 "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted --emit=exe "$project_root/tests/runtime_precise_closure_link.lisp" -o "$work_dir/check$target_suffix"
 run_target "$work_dir/check$target_suffix"
done
printf 'C import discovery links the precise closure constructor and its runtime dependencies (%s)\n' "$target"
