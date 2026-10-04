#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
compiler=${1:-$project_root/build/pslcc-native}
mkdir -p "$project_root/build"
work_dir=$(mktemp -d "$project_root/build/c-output-XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
for level in 0 1; do
  for destination in "$work_dir/output.o" "$work_dir/output with spaces.o"; do
    "$compiler" "-O$level" "$project_root/examples/ffi/source_import.lisp" "$destination"
    cc -O2 -std=c11 -Wall -Wextra -Werror \
      "$project_root/examples/ffi/harness_source_import.c" "$destination" -o "$work_dir/check"
    "$work_dir/check"
  done
  cp "$work_dir/output.o" "$work_dir/saved.o"
  if "$compiler" "-O$level" "$project_root/tests/include/invalid_c_source.lisp" \
      "$work_dir/output.o" >"$work_dir/out" 2>"$work_dir/err"; then
    echo 'invalid C source replaced a previous output' >&2
    exit 1
  fi
  cmp "$work_dir/saved.o" "$work_dir/output.o"
  test -s "$work_dir/err"
  if "$compiler" "-O$level" "$project_root/examples/ffi/source_import.lisp" \
      "$work_dir/missing/output.o" >"$work_dir/out" 2>"$work_dir/err"; then
    echo 'missing output parent was accepted' >&2
    exit 1
  fi
  test ! -e "$work_dir/missing/output.o"
  if find "$work_dir" -name '.psl-native-*' -print | read -r leftover; then
    echo 'C interop left temporary files behind' >&2
    exit 1
  fi
done
echo 'native C output publication, spaced paths, failure preservation and cleanup passed'
