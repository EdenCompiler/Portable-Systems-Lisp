#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
mkdir -p "$project_root/build"
work_dir=$(mktemp -d "$project_root/build/c-output-XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
compile_output() {
  version=$1
  level=$2
  source=$3
  output=$4
  if test "$version" = native; then
    run_compiler_host "$compiler" "-O$level" --target="$target" -c "$source" -o "$output"
  else
    "$project_root/pslcc" "-O$level" --target="$target" -c "$source" -o "$output"
  fi
}
for version in native seed; do
  for level in 0 1; do
    for destination in "$work_dir/output.o" "$work_dir/output with spaces.o"; do
      compile_output "$version" "$level" "$project_root/examples/ffi/source_import.lisp" "$destination"
      for c_level in 0 2; do
        "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
          "$project_root/examples/ffi/harness_source_import.c" "$destination" \
          -o "$work_dir/check$target_suffix"
        run_target "$work_dir/check$target_suffix"
      done
    done
    cp "$work_dir/output.o" "$work_dir/saved.o"
    if compile_output "$version" "$level" "$project_root/tests/include/invalid_c_source.lisp" \
        "$work_dir/output.o" >"$work_dir/out" 2>"$work_dir/err"; then
      echo "$version invalid C source replaced a previous output" >&2
      exit 1
    fi
    cmp "$work_dir/saved.o" "$work_dir/output.o"
    test -s "$work_dir/err"
    if compile_output "$version" "$level" "$project_root/examples/ffi/source_import.lisp" \
        "$work_dir/missing/output.o" >"$work_dir/out" 2>"$work_dir/err"; then
      echo "$version missing output parent was accepted" >&2
      exit 1
    fi
    test ! -e "$work_dir/missing/output.o"
    if find "$work_dir" \( -name '.psl-native-*' -o -name '.psl-ffi-*' \) -print | read -r leftover; then
      echo "$version C interop left temporary files behind" >&2
      exit 1
    fi
  done
done
echo "Native and Stage 0 C output publication, spaced paths, failure preservation and cleanup passed ($target)"
