#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
case $target in
  x86_64-windows-gnu) platform=windows ;;
  *) platform=linux ;;
esac
"$target_cc" -O0 -std=c11 -Wall -Wextra -Werror \
  -c "$project_root/runtime/platform_$platform.c" -o "$work_dir/runtime-platform.o"
runtime_sources="$project_root/runtime/value.c $project_root/runtime/cons.c $project_root/runtime/string.c $project_root/runtime/symbol.c $project_root/runtime/package.c $project_root/runtime/closure.c $project_root/runtime/vector.c $project_root/runtime/values.c $project_root/runtime/gc.c $project_root/runtime/startup.c $work_dir/runtime-platform.o"
sh "$project_root/tests/bootstrap_macro_constant_oracle.sh"
for level in 0 1; do
  for fixture in macros macro_rest macro_optional macro_aux macro_whole macro_control macro_sequence macro_lists macro_declarations macro_keys macro_let macro_nil_key_name macro_eval_when macro_destructuring macro_nil_key_destructuring; do
  source=$project_root/tests/bootstrap_$fixture.lisp
  run_compiler_host "$compiler" "-O$level" --profile=freestanding --target="$target" "$source" "$work_dir/native.o"
  run_compiler_host "$compiler" "-O$level" --profile=freestanding --target="$target" "$source" "$work_dir/repeat.o"
  cmp "$work_dir/native.o" "$work_dir/repeat.o"
  if test -n "${PSL_NATIVE_OBJECT_SNAPSHOT_DIR:-}"; then
    mkdir -p "$PSL_NATIVE_OBJECT_SNAPSHOT_DIR"
    cp "$work_dir/native.o" "$PSL_NATIVE_OBJECT_SNAPSHOT_DIR/$fixture-$level.o"
  fi
  "$project_root/pslcc" "-O$level" --profile=freestanding --target="$target" -c "$source" -o "$work_dir/stage0.o"
  for version in native stage0; do
    "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
      "$project_root/tests/harness_bootstrap_$fixture.c" "$work_dir/$version.o" \
      -o "$work_dir/check$target_suffix"
    run_target "$work_dir/check$target_suffix"
  done
  done
  "$project_root/pslcc" "-O$level" --profile=freestanding --target="$target" -c \
    "$project_root/tests/bootstrap_macro_nil_key_shape.lisp" -o "$work_dir/stage0-shape.o"
  "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
    "$project_root/tests/harness_bootstrap_macro_nil_key_shape.c" "$work_dir/stage0-shape.o" \
    -o "$work_dir/shape-check$target_suffix"
  run_target "$work_dir/shape-check$target_suffix"
  source=$project_root/bootstrap/native-core.lisp
  run_compiler_host "$compiler" "-O$level" --profile=hosted --target="$target" -c "$source" -o "$work_dir/api-native.o"
  "$project_root/pslcc" "-O$level" --profile=hosted --target="$target" -c "$source" -o "$work_dir/api-stage0.o"
  for version in native stage0; do
    for fixture in macro_api macro_optional_api macro_aux_api macro_whole_api macro_control_api macro_sequence_api macro_lists_api macro_declarations_api macro_keys_api macro_let_api macro_destructuring_api macro_nil_key_destructuring_api macro_pattern_prefix_api; do
      "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_$fixture.c" "$work_dir/api-$version.o" \
        $runtime_sources \
        -o "$work_dir/api-check$target_suffix"
      run_target "$work_dir/api-check$target_suffix"
    done
  done
  for source in "$project_root"/tests/bootstrap_macro_errors/*.lisp; do
    for version in native stage0; do
      output=$work_dir/$version-rejected.o
      rm -f "$output"
      if test "$version" = native; then
        if run_compiler_host "$compiler" "-O$level" --profile=freestanding --target="$target" "$source" "$output" >"$work_dir/out" 2>"$work_dir/err"; then
          echo "native compiler accepted invalid macro source: $source" >&2
          exit 1
        fi
      elif "$project_root/pslcc" "-O$level" --profile=freestanding --target="$target" -c "$source" -o "$output" >"$work_dir/out" 2>"$work_dir/err"; then
        echo "Stage 0 accepted invalid macro source: $source" >&2
        exit 1
      fi
      test ! -e "$output"
      test -s "$work_dir/err"
    done
  done
done
# Hosted macro registries and lexical slots use the checked source bound,
# not the former fixed limits of 256 definitions and 128 bindings.
capacity_source=$work_dir/macro-capacity.lisp
: >"$capacity_source"
i=0
while test "$i" -lt 260; do
  printf '(defmacro cap_%03d () 1)\n' "$i" >>"$capacity_source"
  i=$((i + 1))
done
printf '(defun macro_registry_capacity_answer () (declare (returns u64) (c-export :c)) (cap_259))\n' >>"$capacity_source"
printf '(defmacro many (first' >>"$capacity_source"
i=0
while test "$i" -lt 129; do
  printf ' p%03d' "$i" >>"$capacity_source"
  i=$((i + 1))
done
printf ') first)\n(defun macro_binding_capacity_answer () (declare (returns u64) (c-export :c)) (many 1' >>"$capacity_source"
i=0
while test "$i" -lt 129; do
  printf ' 2' >>"$capacity_source"
  i=$((i + 1))
done
printf '))\n' >>"$capacity_source"
for level in 0 1; do
  run_compiler_host "$compiler" "-O$level" --profile=freestanding --target="$target" \
    -c "$capacity_source" -o "$work_dir/capacity-native.o"
  "$project_root/pslcc" "-O$level" --profile=freestanding --target="$target" \
    -c "$capacity_source" -o "$work_dir/capacity-stage0.o"
  for version in native stage0; do
    "$target_cc" -O2 -std=c11 -Wall -Wextra -Werror \
      "$project_root/tests/harness_bootstrap_macro_capacity.c" \
      "$work_dir/capacity-$version.o" -o "$work_dir/capacity-check$target_suffix"
    run_target "$work_dir/capacity-check$target_suffix"
  done
done
# Prove Linux native expansion needs no host Lisp executable or tool subprocess.
if test "$compiler_host_target" = x86_64-linux-gnu; then
  for fixture in macros macro_rest macro_optional macro_aux macro_whole macro_control macro_sequence macro_lists macro_declarations macro_keys macro_let macro_nil_key_name macro_eval_when macro_destructuring macro_nil_key_destructuring; do
    PATH=/nonexistent "$compiler" --target="$target" "$project_root/tests/bootstrap_$fixture.lisp" "$work_dir/without-host-lisp.o"
  done
fi
echo "build-host macro expansion passed ($target)"
