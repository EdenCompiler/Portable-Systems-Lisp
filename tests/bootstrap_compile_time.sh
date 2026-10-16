#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
python3 - "$work_dir" <<'PYTHON'
from pathlib import Path
import sys
root = Path(sys.argv[1])
definition = '(defmacro answer () 42)'
tail = '(defun result () (declare (returns u64) (c-export :c)) 42)\n'
invalid = [
    '(eval-when)', '(eval-when :compile-toplevel)',
    '(eval-when (:load-toplevel) ' + definition + ')',
    '(eval-when (:execute) ' + definition + ')',
    '(eval-when (:compile-toplevel :load-toplevel) ' + definition + ')',
    '(eval-when (:compile-toplevel :compile-toplevel) ' + definition + ')',
    '(eval-when (:|compile-toplevel|) ' + definition + ')',
    '(eval-when (compile-toplevel) ' + definition + ')',
    '(eval-when (:compile-toplevel) 42)',
    '(eval-when (:compile-toplevel) (progn ' + definition + '))',
    '(eval-when (:compile-toplevel) (defmacro broken (t) 42))',
    '(eval-when (:compile-toplevel) ' + definition + ' 42)',
]
for index, form in enumerate(invalid):
    (root / f'reject-{index}.lisp').write_text(form + '\n' + tail)
for index, parameters in enumerate([
        '(t)', '(&whole t)', '(&rest t)', '(&body t)', '(&environment t)',
        '(&optional t)', '(&optional (x nil t))', '(&key ((:x t)))',
        '(&key (x nil t))', '(&aux t)', '((left t))']):
    form = '(defmacro invalid ' + parameters + ' 42)\n'
    (root / f'reject-constant-{index}.lisp').write_text(form + tail)
PYTHON
source=$project_root/tests/bootstrap_macro_eval_when.lisp
for level in 0 1; do
  # Preserve the seed's existing host-Lisp destructuring support, which remains
  # outside the native macro subset. Binding validation must not change it.
  "$project_root/pslcc" "-O$level" --target="$target" -c \
    "$project_root/tests/seed_macro_patterns.lisp" -o "$work_dir/seed-patterns.o"
  for c_level in 0 2; do
    "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
      "$project_root/tests/harness_seed_macro_patterns.c" \
      "$work_dir/seed-patterns.o" -o "$work_dir/patterns$target_suffix"
    run_target "$work_dir/patterns$target_suffix"
  done
  for version in native seed; do
    for repeat in first second; do
      object=$work_dir/$version-$repeat.o
      if test "$version" = native; then
        run_compiler_host "$compiler" "-O$level" --target="$target" -c "$source" -o "$object"
      else
        "$project_root/pslcc" "-O$level" --target="$target" -c "$source" -o "$object"
      fi
    done
    cmp "$work_dir/$version-first.o" "$work_dir/$version-second.o"
    for c_level in 0 2; do
      "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_macro_eval_when.c" \
        "$work_dir/$version-first.o" -o "$work_dir/check$target_suffix"
      run_target "$work_dir/check$target_suffix"
    done
    for invalid in "$work_dir"/reject-*.lisp; do
      for repeat in first second; do
        printf 'retain the prior artifact\n' > "$work_dir/preserved"
        cp "$work_dir/preserved" "$work_dir/expected"
        if test "$version" = native; then
          if run_compiler_host "$compiler" "-O$level" --target="$target" -c "$invalid" \
              -o "$work_dir/preserved" > "$work_dir/out" 2> "$work_dir/$repeat.error"; then
            echo "native compiler accepted invalid compile-time wrapper: $invalid" >&2
            exit 1
          else
            test "$?" -eq 1
          fi
        else
          if "$project_root/pslcc" "-O$level" --target="$target" -c "$invalid" \
              -o "$work_dir/preserved" > "$work_dir/out" 2> "$work_dir/$repeat.error"; then
            echo "Stage 0 accepted invalid compile-time wrapper: $invalid" >&2
            exit 1
          else
            test "$?" -eq 1
          fi
        fi
        cmp "$work_dir/expected" "$work_dir/preserved"
        test ! -s "$work_dir/out"
        test -s "$work_dir/$repeat.error"
      done
      cmp "$work_dir/first.error" "$work_dir/second.error"
    done
  done
  if test "$compiler_host_target" = x86_64-linux-gnu; then
    PATH=/nonexistent "$compiler" "-O$level" --target="$target" -c "$source" \
      -o "$work_dir/without-host-lisp.o"
  fi
done
printf 'Compile-toplevel macro wrappers preserve source order and reject unsupported forms (%s)\n' "$target"
