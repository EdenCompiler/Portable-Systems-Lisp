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
  for name in float_reader float_memory; do
    run_compiler_host "$compiler" "-O$level" --target="$target" \
      "$project_root/tests/bootstrap_$name.lisp" "$work_dir/native.o"
    run_compiler_host "$compiler" "-O$level" --target="$target" \
      "$project_root/tests/bootstrap_$name.lisp" "$work_dir/repeat.o"
    cmp "$work_dir/native.o" "$work_dir/repeat.o"
    "$project_root/pslcc" "-O$level" --target="$target" -c \
      "$project_root/tests/bootstrap_$name.lisp" -o "$work_dir/stage0.o"
    for version in native stage0; do
      "$target_cc" -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_$name.c" "$work_dir/$version.o" \
        -o "$work_dir/check$target_suffix"
      run_target "$work_dir/check$target_suffix"
    done
  done
done
for source in "$project_root"/tests/bootstrap_float_errors/*.lisp; do
  if run_compiler_host "$compiler" --target="$target" "$source" \
      "$work_dir/invalid.o" >"$work_dir/error.log" 2>&1; then
    echo "native accepted invalid floating source: $source" >&2; exit 1
  fi
  test ! -e "$work_dir/invalid.o"
  if "$project_root/pslcc" --target="$target" -c "$source" \
      -o "$work_dir/invalid.o" >"$work_dir/error.log" 2>&1; then
    echo "Stage 0 accepted invalid floating source: $source" >&2; exit 1
  fi
  test ! -e "$work_dir/invalid.o"
done
# Keep floating ABI signatures gated until their separate C interop slice.
cat > "$work_dir/pending-abi.lisp" <<'LISP'
(defun pending (x) (declare (type f32 x) (returns c-int)) 0)
LISP
if run_compiler_host "$compiler" --target="$target" "$work_dir/pending-abi.lisp" \
    "$work_dir/pending.o" >"$work_dir/error.log" 2>&1; then
  echo 'native accepted an unimplemented floating ABI signature' >&2; exit 1
fi
test ! -e "$work_dir/pending.o"
echo "native floating literal, memory, and data checks passed ($target)"
