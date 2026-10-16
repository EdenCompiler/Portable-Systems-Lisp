#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
growth_compiler=${1:-$project_root/build/pslcc-native}
stage0_compiler=${2:-$project_root/pslcc}
target=${3:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
for level in 0 1; do
  for depth in 3 4 5 6 7 8 9 10; do
    expr=1
    i=0
    while test "$i" -lt "$depth"; do
      expr="(m $expr)"
      i=$((i + 1))
    done
    source=$work_dir/nested-$depth.lisp
    cat >"$source" <<EOF_SOURCE
(defmacro m (x) (list 'wrap+ x x))
(defun nested_result () (declare (returns u64) (c-export :c)) $expr)
EOF_SOURCE
    expected=1
    i=0
    while test "$i" -lt "$depth"; do
      expected=$((expected * 2))
      i=$((i + 1))
    done
    for compiler in native stage0; do
      object=$work_dir/$compiler-$depth-$level.o
      executable=$work_dir/$compiler-$depth-$level$target_suffix
      if test "$compiler" = native; then
        run_compiler_host "$growth_compiler" "-O$level" --target="$target" -c "$source" -o "$object"
        run_compiler_host "$growth_compiler" "-O$level" --target="$target" -c "$source" -o "$work_dir/repeat.o"
        cmp "$object" "$work_dir/repeat.o"
      else
        "$stage0_compiler" "-O$level" --target="$target" -c "$source" -o "$object"
      fi
      for c_level in 0 2; do
        "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
          -DEXPECTED="$expected" "$project_root/tests/harness_bootstrap_nested_macro_growth.c" \
          "$object" -o "$executable"
        run_target "$executable"
      done
    done
  done
done
# Rejected source must not replace an existing user output.
invalid=$work_dir/invalid.lisp
cat >"$invalid" <<'EOF_INVALID'
(defun nested_result () (declare (returns u64) (c-export :c)) (unknown-call 7))
EOF_INVALID
for compiler in native stage0; do
  output=$work_dir/preserved.o
  printf 'keep-existing-output\n' >"$output"
  if test "$compiler" = native; then
    if run_compiler_host "$growth_compiler" -O0 --target="$target" -c "$invalid" -o "$output" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
      echo "native compiler accepted invalid macro-growth control" >&2
      exit 1
    else
      test "$?" -eq 1
    fi
  elif "$stage0_compiler" -O0 --target="$target" -c "$invalid" -o "$output" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "compiler accepted invalid macro-growth control: $compiler" >&2
    exit 1
  else
    test "$?" -eq 1
  fi
  test "$(cat "$output")" = keep-existing-output
  test -s "$work_dir/stderr"
done
# IR dumping and macro growth share a reprepare path. The AST arena must retain
# its enlarged capacity after the IR buffer independently grows and retries.
source=$work_dir/nested-8-dump.lisp
expr=1
i=0
while test "$i" -lt 8; do expr="(m $expr)"; i=$((i + 1)); done
cat >"$source" <<EOF_DUMP
(defmacro m (x) (list 'wrap+ x x))
(defun nested_result () (declare (returns u64) (c-export :c)) $expr)
EOF_DUMP
run_compiler_host "$growth_compiler" -O0 --target="$target" -c --dump-ir=all "$source" -o "$work_dir/nested-dump.o" \
  >"$work_dir/ir" 2>"$work_dir/ir-error"
test -s "$work_dir/nested-dump.o"
grep -q '^HIR nested_result' "$work_dir/ir"
test ! -s "$work_dir/ir-error"
if test "$compiler_host_target" = x86_64-linux-gnu && test "$target" = x86_64-linux-gnu; then
  for c_level in 0 2; do
    "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
      "$project_root/tests/harness_bootstrap_macro_capacity_api.c" \
      "${PSL_NATIVE_CORE_OBJECT:-$project_root/build/native-core.o}" \
      "${PSL_NATIVE_HOST_OBJECT:-$project_root/build/native-host.o}" \
      -o "$work_dir/macro-capacity-api"
    "$work_dir/macro-capacity-api"
  done
fi
printf 'hosted nested macro capacity retry passed (depths 3-10, O0/O1, native/Stage0; %s)\n' "$target"
