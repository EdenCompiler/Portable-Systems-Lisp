#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
source=$project_root/tests/bootstrap_answer.lisp

for level in 0 1; do
  run_compiler_host "$compiler" "-O$level" -c "$source" \
    --target="$target" -o "$work_dir/plain-$level.o"
  run_compiler_host "$compiler" "-O$level" -c "$source" \
    --target="$target" -o "$work_dir/all-$level.o" --dump-ir=all \
    >"$work_dir/all-$level.txt"
  cmp "$work_dir/plain-$level.o" "$work_dir/all-$level.o"
  for stage in hir ssa lir; do
    run_compiler_host "$compiler" "-O$level" -c "$source" \
      --target="$target" -o "$work_dir/$stage-$level.o" \
      "--dump-ir=$stage" >"$work_dir/$stage-$level.txt"
    cmp "$work_dir/plain-$level.o" "$work_dir/$stage-$level.o"
    grep -q "^$(printf '%s' "$stage" | tr '[:lower:]' '[:upper:]') " \
      "$work_dir/$stage-$level.txt"
  done
  grep -q '^HIR ' "$work_dir/all-$level.txt"
  grep -q '^SSA ' "$work_dir/all-$level.txt"
  grep -q '^LIR ' "$work_dir/all-$level.txt"
  run_compiler_host "$compiler" "-O$level" -c "$source" \
    --target="$target" -o "$work_dir/repeat-$level.o" --dump-ir=all \
    >"$work_dir/repeat-$level.txt"
  cmp "$work_dir/all-$level.txt" "$work_dir/repeat-$level.txt"
  cmp "$work_dir/plain-$level.o" "$work_dir/repeat-$level.o"
done

if run_compiler_host "$compiler" -c "$source" -o "$work_dir/bad.o" \
    --dump-ir=none >"$work_dir/bad.stdout" 2>"$work_dir/bad.stderr"; then
  echo 'native CLI accepted an unsupported IR dump mode' >&2
  exit 1
else
  test "$?" -eq 1
fi
test ! -s "$work_dir/bad.stdout"
grep -q 'unknown IR dump mode none' "$work_dir/bad.stderr"

# Exercise generated bodies through the actual CLI and the current owned dumper.
for level in 0 1; do
  closure_source=$project_root/tests/bootstrap_native_closures.lisp
  run_compiler_host "$compiler" "-O$level" -c "$closure_source" \
    --profile=hosted --target="$target" -o "$work_dir/closures.o"
  run_compiler_host "$compiler" "-O$level" -c "$closure_source" \
    --profile=hosted --target="$target" -o "$work_dir/closures-dump.o" \
    --dump-ir=all > "$work_dir/closures.ir"
  cmp "$work_dir/closures.o" "$work_dir/closures-dump.o"
  grep -q '^HIR LAMBDA#' "$work_dir/closures.ir"
  grep -q '^SSA LAMBDA#' "$work_dir/closures.ir"
  grep -q '^LIR LAMBDA#' "$work_dir/closures.ir"
  grep -q 'FUNCTION-ADDRESS' "$work_dir/closures.ir"
done

# A valid rooted list requires more text than the initial source-derived arena.
# The controller grows it and recompiles the same assembled source snapshot.
{
  printf '(defun ir_capacity_answer ()(declare(returns value)(c-export :c))'
  n=0
  while [ "$n" -lt 32 ]; do printf '(cons 1 '; n=$((n + 1)); done
  printf 'nil'
  n=0
  while [ "$n" -lt 32 ]; do printf ')'; n=$((n + 1)); done
  printf ')\n'
} > "$work_dir/capacity.lisp"
run_compiler_host "$compiler" -O0 -c "$work_dir/capacity.lisp" \
  --profile=hosted --target="$target" -o "$work_dir/capacity-valid.o"
run_compiler_host "$compiler" -O0 -c "$work_dir/capacity.lisp" \
  --profile=hosted --target="$target" -o "$work_dir/capacity-dump.o" \
  --dump-ir=all > "$work_dir/capacity.ir"
cmp "$work_dir/capacity-valid.o" "$work_dir/capacity-dump.o"
source_size=$(wc -c < "$work_dir/capacity.lisp")
text_size=$(wc -c < "$work_dir/capacity.ir")
test "$text_size" -gt "$((64 * source_size + 4096))"
cat > "$work_dir/capacity-caller.c" <<'SOURCE'
#include "psl_runtime.h"
extern psl_value ir_capacity_answer(void);
int main(void) {
    psl_value list = ir_capacity_answer();
    psl_root root;
    psl_rt_push_roots(&root, &list, 1);
    psl_rt_collect_precise();
    psl_value cursor = list;
    unsigned count = 0;
    while (cursor != PSL_NIL && count < 33) {
        if (psl_rt_unbox_fixnum(psl_rt_car(cursor)) != 1) return 1;
        cursor = psl_rt_cdr(cursor);
        ++count;
    }
    psl_rt_pop_roots(&root);
    psl_rt_collect_precise();
    return count == 32 && cursor == PSL_NIL && !psl_rt_live_objects() ? 0 : 1;
}
SOURCE
case $target in x86_64-windows-gnu) platform=windows ;; *) platform=linux ;; esac
"$target_cc" -O0 -c "$project_root/runtime/platform_$platform.c" -o "$work_dir/platform.o"
for version in valid dump; do
  "$target_cc" -O2 -Wall -Wextra -Werror -I "$project_root/runtime" \
    "$work_dir/capacity-caller.c" "$work_dir/capacity-$version.o" \
    "$project_root/runtime/value.c" "$project_root/runtime/cons.c" \
    "$project_root/runtime/gc.c" "$project_root/runtime/startup.c" \
    "$work_dir/platform.o" -o "$work_dir/capacity-check$target_suffix"
  run_target "$work_dir/capacity-check$target_suffix"
done
printf 'preserve existing object\n' > "$work_dir/preserved.o"
cp "$work_dir/preserved.o" "$work_dir/expected.o"
if run_compiler_host "$compiler" -c "$project_root/tests/bootstrap_wrong_arity.lisp" \
    --target="$target" -o "$work_dir/preserved.o" --dump-ir=all \
    > "$work_dir/invalid.stdout" 2> "$work_dir/invalid.stderr"; then
  echo 'IR capture accepted invalid source' >&2
  exit 1
else
  test "$?" -eq 1
fi
test ! -s "$work_dir/invalid.stdout"
cmp "$work_dir/expected.o" "$work_dir/preserved.o"

if test "${PSL_SKIP_NATIVE_CORE_DUMP:-0}" = 1; then
  printf 'Native IR CLI selectors and object identity passed (%s; full-core dump run separately)\n' "$target"
else
  # Exercise the capacity calculation on the largest owned compilation unit.
  run_compiler_host "$compiler" -O1 --profile=hosted -c "$project_root/bootstrap/native-core.lisp" \
    --target="$target" -o "$work_dir/native-core.o" --dump-ir=all \
    >"$work_dir/native-core.ir"
  test -s "$work_dir/native-core.o"
  grep -q '^HIR ' "$work_dir/native-core.ir"
  grep -q '^SSA ' "$work_dir/native-core.ir"
  grep -q '^LIR ' "$work_dir/native-core.ir"
  printf 'Native IR CLI stages, repeatability, object identity and full-core capacity passed (%s)\n' "$target"
fi
