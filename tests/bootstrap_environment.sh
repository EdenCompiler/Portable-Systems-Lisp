#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
cd "$project_root"
sbcl --script tests/bootstrap_environment_catalogue.lisp "$work_dir/catalogue.tsv"
sbcl --script tests/bootstrap_environment_oracle.lisp "$work_dir/oracle.tsv"
catalogue=$work_dir/catalogue.tsv
oracle=$work_dir/oracle.tsv
if [ "$target" = x86_64-windows-gnu ]; then
  catalogue=$(winepath -w "$catalogue")
  oracle=$(winepath -w "$oracle")
fi
for level in 0 1; do
  source=$project_root/bootstrap/frontend/environment/read_symbols.lisp
  run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$work_dir/native.o"
  run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$work_dir/repeat.o"
  cmp "$work_dir/native.o" "$work_dir/repeat.o"
  "$project_root/pslcc" "-O$level" --target="$target" -c "$source" -o "$work_dir/stage0.o"
  for version in native stage0; do
    for name in environment environment_seed environment_reader environment_oracle; do
      "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_$name.c" "$work_dir/$version.o" \
        -o "$work_dir/check$target_suffix"
      if [ "$name" = environment_seed ]; then
        run_target "$work_dir/check$target_suffix" "$catalogue"
      elif [ "$name" = environment_oracle ]; then
        run_target "$work_dir/check$target_suffix" "$oracle"
      else
        run_target "$work_dir/check$target_suffix"
      fi
    done
  done
done
echo "native build-host package and symbol reader checks passed ($target)"
