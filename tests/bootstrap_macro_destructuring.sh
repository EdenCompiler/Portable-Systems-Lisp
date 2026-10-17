#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
source=$project_root/tests/bootstrap_macro_destructuring.lisp
nil_key_source=$project_root/tests/bootstrap_macro_nil_key_destructuring.lisp
shape_source=$project_root/tests/bootstrap_macro_nil_key_shape.lisp
primitive_source=$project_root/tests/bootstrap_macro_primitive_eval.lisp
for level in 0 1; do
  for version in native stage0; do
    object=$work_dir/$version-$level.o
    if test "$version" = native; then
      run_compiler_host "$compiler" "-O$level" --target="$target" -c "$source" -o "$object"
    else
      "$project_root/pslcc" "-O$level" --target="$target" -c "$source" -o "$object"
    fi
    for c_level in 0 2; do
      "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_macro_destructuring.c" "$object" \
        -o "$work_dir/check$target_suffix"
      run_target "$work_dir/check$target_suffix"
    done
  done
  for version in native stage0; do
    object=$work_dir/nil-key-$version-$level.o
    if test "$version" = native; then
      run_compiler_host "$compiler" "-O$level" --target="$target" -c "$nil_key_source" -o "$object"
    else
      "$project_root/pslcc" "-O$level" --target="$target" -c "$nil_key_source" -o "$object"
    fi
    for c_level in 0 2; do
      "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_macro_nil_key_destructuring.c" "$object" \
        -o "$work_dir/nil-key-check$target_suffix"
      run_target "$work_dir/nil-key-check$target_suffix"
    done
  done
  for version in native stage0; do
    api_object=$work_dir/api-$version-$level.o
    if test "$version" = native; then
      bootstrap_fixture_compile native "$compiler" "$level" "$target" hosted \
        "$project_root/bootstrap/native-core.lisp" "$api_object"
    else
      bootstrap_fixture_compile seed "$project_root/pslcc" "$level" "$target" hosted \
        "$project_root/bootstrap/native-core.lisp" "$api_object"
    fi
    for c_level in 0 2; do
      bootstrap_link_runtime "$target_cc_binary" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_macro_destructuring_api.c" "$api_object" \
        -o "$work_dir/api-check$target_suffix"
      run_target "$work_dir/api-check$target_suffix"
      bootstrap_link_runtime "$target_cc_binary" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_macro_nil_key_destructuring_api.c" "$api_object" \
        -o "$work_dir/nil-key-api-check$target_suffix"
      run_target "$work_dir/nil-key-api-check$target_suffix"
      bootstrap_link_runtime "$target_cc_binary" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_macro_pattern_prefix_api.c" "$api_object" \
        -o "$work_dir/prefix-api-check$target_suffix"
      run_target "$work_dir/prefix-api-check$target_suffix"
    done
  done
  for version in native stage0; do
    object=$work_dir/shape-$version-$level.o
    if test "$version" = native; then
      run_compiler_host "$compiler" "-O$level" --target="$target" -c "$shape_source" -o "$object"
    else
      "$project_root/pslcc" "-O$level" --target="$target" -c "$shape_source" -o "$object"
    fi
    for c_level in 0 2; do
      "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_macro_nil_key_shape.c" "$object" \
        -o "$work_dir/shape-check$target_suffix"
      run_target "$work_dir/shape-check$target_suffix"
    done
  done
  for version in native stage0; do
    object=$work_dir/primitive-$version-$level.o
    if test "$version" = native; then
      run_compiler_host "$compiler" "-O$level" --target="$target" -c "$primitive_source" -o "$object"
    else
      "$project_root/pslcc" "-O$level" --target="$target" -c "$primitive_source" -o "$object"
    fi
    for c_level in 0 2; do
      "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_bootstrap_macro_primitive_eval.c" "$object" \
        -o "$work_dir/primitive-check$target_suffix"
      run_target "$work_dir/primitive-check$target_suffix"
    done
  done
done
for fixture in "$project_root"/tests/bootstrap_macro_errors/destructuring-*.lisp; do
  for version in native stage0; do
    output=$work_dir/rejected.o
    rm -f "$output"
    if test "$version" = native; then
      if run_compiler_host "$compiler" -O0 --target="$target" -c "$fixture" -o "$output" \
           >"$work_dir/out" 2>"$work_dir/err"; then
        echo "native compiler accepted invalid destructuring source: $fixture" >&2
        exit 1
      fi
    elif "$project_root/pslcc" -O0 --target="$target" -c "$fixture" -o "$output" \
         >"$work_dir/out" 2>"$work_dir/err"; then
      echo "Stage 0 accepted invalid destructuring source: $fixture" >&2
      exit 1
    fi
    test ! -e "$output"
    test -s "$work_dir/err"
  done
done
for fixture in \
  "$project_root/tests/bootstrap_macro_errors/primitive-equal-arity.lisp" \
  "$project_root/tests/bootstrap_macro_errors/primitive-length-type.lisp" \
  "$project_root/tests/bootstrap_macro_errors/primitive-length-dotted.lisp" \
  "$project_root/tests/bootstrap_macro_errors/primitive-second-type.lisp"; do
  for version in native stage0; do
    output=$work_dir/rejected-primitive.o
    printf 'preserve-output\n' >"$output"
    if test "$version" = native; then
      if run_compiler_host "$compiler" -O0 --target="$target" -c "$fixture" -o "$output" \
           >"$work_dir/out" 2>"$work_dir/err"; then
        echo "native compiler accepted invalid macro primitive source: $fixture" >&2
        exit 1
      else
        status=$?
        test "$status" -eq 1
      fi
    else
      if "$project_root/pslcc" -O0 --target="$target" -c "$fixture" -o "$output" \
           >"$work_dir/out" 2>"$work_dir/err"; then
        echo "Stage 0 accepted invalid macro primitive source: $fixture" >&2
        exit 1
      else
        status=$?
        test "$status" -eq 1
      fi
    fi
    test "$(cat "$output")" = preserve-output
    test -s "$work_dir/err"
  done
done
echo "native macro destructuring passed ($target)"
