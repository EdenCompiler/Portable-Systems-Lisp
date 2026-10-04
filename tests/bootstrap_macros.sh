#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
for level in 0 1; do
  for fixture in macros macro_rest macro_optional macro_aux; do
  source=$project_root/tests/bootstrap_$fixture.lisp
  run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$work_dir/native.o"
  run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$work_dir/repeat.o"
  cmp "$work_dir/native.o" "$work_dir/repeat.o"
  if test -n "${PSL_NATIVE_OBJECT_SNAPSHOT_DIR:-}"; then
    mkdir -p "$PSL_NATIVE_OBJECT_SNAPSHOT_DIR"
    cp "$work_dir/native.o" "$PSL_NATIVE_OBJECT_SNAPSHOT_DIR/$fixture-$level.o"
  fi
  "$project_root/pslcc" "-O$level" --target="$target" -c "$source" -o "$work_dir/stage0.o"
  for version in native stage0; do
    "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
      "$project_root/tests/harness_bootstrap_$fixture.c" "$work_dir/$version.o" \
      -o "$work_dir/check$target_suffix"
    run_target "$work_dir/check$target_suffix"
  done
  done
  source=$project_root/bootstrap/native-core.lisp
  run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$work_dir/api-native.o"
  "$project_root/pslcc" "-O$level" --target="$target" -c "$source" -o "$work_dir/api-stage0.o"
  for version in native stage0; do
    for fixture in macro_api macro_optional_api macro_aux_api; do
      "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_$fixture.c" "$work_dir/api-$version.o" \
        -o "$work_dir/api-check$target_suffix"
      run_target "$work_dir/api-check$target_suffix"
    done
  done
  for source in "$project_root"/tests/bootstrap_macro_errors/*.lisp; do
    for version in native stage0; do
      output=$work_dir/$version-rejected.o
      rm -f "$output"
      if test "$version" = native; then
        if run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$output" >"$work_dir/out" 2>"$work_dir/err"; then
          echo "native compiler accepted invalid macro source: $source" >&2
          exit 1
        fi
      elif "$project_root/pslcc" "-O$level" --target="$target" -c "$source" -o "$output" >"$work_dir/out" 2>"$work_dir/err"; then
        echo "Stage 0 accepted invalid macro source: $source" >&2
        exit 1
      fi
      test ! -e "$output"
      test -s "$work_dir/err"
    done
  done
done
# Prove Linux native expansion needs no host Lisp executable or tool subprocess.
if test "$compiler_host_target" = x86_64-linux-gnu; then
  for fixture in macros macro_rest macro_optional macro_aux; do
    PATH=/nonexistent "$compiler" --target="$target" "$project_root/tests/bootstrap_$fixture.lisp" "$work_dir/without-host-lisp.o"
  done
fi
echo "build-host macro expansion passed ($target)"
