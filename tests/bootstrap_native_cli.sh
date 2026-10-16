#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
mkdir "$work_dir/paths with spaces"
source=$work_dir/paths\ with\ spaces/source.lisp
cp "$project_root/tests/bootstrap_answer.lisp" "$source"

for level in 0 1; do
  run_compiler_host "$compiler" "-O$level" --target="$target" \
    "$source" "$work_dir/legacy.o"
  run_compiler_host "$compiler" -c "$source" --target "$target" \
    -o "$work_dir/paths with spaces/modern.o" "-O$level"
  cmp "$work_dir/legacy.o" "$work_dir/paths with spaces/modern.o"
  run_compiler_host "$compiler" --profile hosted -o "$work_dir/hosted.o" \
    --target "$target" -c "$source" "-O$level"
  "$project_root/pslcc" "-O$level" --target="$target" -c "$source" \
    -o "$work_dir/seed.o"
  for version in legacy hosted seed; do
    "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
      "$project_root/tests/harness_bootstrap_answer.c" "$work_dir/$version.o" \
      -o "$work_dir/check$target_suffix"
    run_target "$work_dir/check$target_suffix"
  done
  run_compiler_host "$compiler" "-O$level" --target="$target" \
    "$project_root/bootstrap/host/compiler.lisp" "$work_dir/native-driver.o"
  "$project_root/pslcc" "-O$level" --target="$target" -c \
    "$project_root/bootstrap/host/compiler.lisp" -o "$work_dir/seed-driver.o"
  for version in native seed; do
    for c_level in 0 2; do
      "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_compiler.c" \
        "$work_dir/$version-driver.o" -o "$work_dir/controller$target_suffix"
      run_target "$work_dir/controller$target_suffix"
    done
    if test "$target" = x86_64-linux-gnu; then
      "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
        -DPSL_TEST_ALLOCATOR_FAULTS \
        "$project_root/tests/harness_bootstrap_compiler.c" \
        "$work_dir/$version-driver.o" -Wl,--wrap=calloc -Wl,--wrap=free \
        -o "$work_dir/controller-faults"
      run_target "$work_dir/controller-faults"
    fi
  done
done

printf 'preserve an existing output\n' > "$work_dir/preserved.o"
cp "$work_dir/preserved.o" "$work_dir/expected"
if run_compiler_host "$compiler" -c "$source" -o "$work_dir/preserved.o" \
    --target >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'native CLI accepted a missing target value' >&2
  exit 1
else
  test "$?" -eq 1
fi
cmp "$work_dir/expected" "$work_dir/preserved.o"
grep -q '^Usage: pslcc-native ' "$work_dir/stderr"
printf 'Native object CLI, parser ABI, profiles, option order and cleanup passed (%s)\n' "$target"
