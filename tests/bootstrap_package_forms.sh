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
sbcl --script tests/bootstrap_package_forms_oracle.lisp
python3 - "$work_dir" <<'PYTHON'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
body = '(defun capacity_answer () (declare (returns u64) (c-export :c)) 42)\n'
for count, name in ((123, "capacity.lisp"), (124, "exhausted.lisp")):
    forms = ''.join(f'(defpackage "PSL.CAP.{index}" (:use))\n' for index in range(count))
    (root / name).write_text(forms + body)
PYTHON
for level in 0 1; do
  run_compiler_host "$compiler" "-O$level" --target="$target" "$work_dir/capacity.lisp" "$work_dir/capacity.o"
  rm -f "$work_dir/exhausted.o"
  if run_compiler_host "$compiler" "-O$level" --target="$target" "$work_dir/exhausted.lisp" "$work_dir/exhausted.o" >"$work_dir/out" 2>"$work_dir/err"; then
    echo "native package arena overflow was accepted" >&2
    exit 1
  fi
  test ! -e "$work_dir/exhausted.o"
  test -s "$work_dir/err"
  for source in "$project_root"/tests/bootstrap_package_form_errors/*.lisp; do
    for version in native stage0; do
      output=$work_dir/$version-rejected.o
      rm -f "$output"
      if test "$version" = native; then
        if run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$output" >"$work_dir/out" 2>"$work_dir/err"; then
          echo "native compiler accepted invalid source packages: $source" >&2
          exit 1
        fi
      elif "$project_root/pslcc" "-O$level" --target="$target" -c "$source" -o "$output" >"$work_dir/out" 2>"$work_dir/err"; then
        echo "Stage 0 accepted invalid source packages: $source" >&2
        exit 1
      fi
      test ! -e "$output"
      test -s "$work_dir/err"
    done
  done
  source=$project_root/tests/bootstrap_package_forms.lisp
  run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$work_dir/native.o"
  run_compiler_host "$compiler" "-O$level" --target="$target" "$source" "$work_dir/repeat.o"
  cmp "$work_dir/native.o" "$work_dir/repeat.o"
  if test -n "${PSL_NATIVE_OBJECT_SNAPSHOT_DIR:-}"; then
    mkdir -p "$PSL_NATIVE_OBJECT_SNAPSHOT_DIR"
    cp "$work_dir/native.o" "$PSL_NATIVE_OBJECT_SNAPSHOT_DIR/package-forms-$level.o"
  fi
  "$project_root/pslcc" "-O$level" --target="$target" -c "$source" -o "$work_dir/stage0.o"
  for version in native stage0; do
    "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
      "$project_root/tests/harness_bootstrap_package_forms.c" "$work_dir/$version.o" \
      -o "$work_dir/check$target_suffix"
    run_target "$work_dir/check$target_suffix"
  done
done
echo "ordered source package forms passed ($target)"
