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
  run_compiler_host "$compiler" "-O$level" --target="$target" \
    "$project_root/tests/bootstrap_c_aliases.lisp" "$work_dir/native.o"
  run_compiler_host "$compiler" "-O$level" --target="$target" \
    "$project_root/tests/bootstrap_c_aliases.lisp" "$work_dir/repeat.o"
  cmp "$work_dir/native.o" "$work_dir/repeat.o"
  "$project_root/pslcc" "-O$level" --target="$target" -c \
    "$project_root/tests/bootstrap_c_aliases.lisp" -o "$work_dir/stage0.o"
  for version in native stage0; do
    "$target_cc" -std=c11 -Wall -Wextra -Werror \
      "$project_root/tests/harness_bootstrap_c_aliases.c" \
      "$work_dir/$version.o" -o "$work_dir/check$target_suffix"
    run_target "$work_dir/check$target_suffix"
  done
done
# A long literal fits LP64 but is outside the Windows LLP64 signed range.
cat > "$work_dir/long-range.lisp" <<'LISP'
(defun answer () (declare (returns c-long) (c-export :c)) 2147483648)
LISP
if test "$target" = x86_64-windows-gnu; then
  if run_compiler_host "$compiler" --target="$target" \
      "$work_dir/long-range.lisp" "$work_dir/range.o" >"$work_dir/range.log" 2>&1; then
    echo 'native accepted out-of-range Windows C long literal' >&2; exit 1
  fi
  test ! -e "$work_dir/range.o"
else
  run_compiler_host "$compiler" --target="$target" \
    "$work_dir/long-range.lisp" "$work_dir/range.o"
fi
echo "native C integer aliases and ABI layout passed ($target)"
