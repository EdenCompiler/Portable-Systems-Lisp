#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

build_driver() {
  cc -Wall -Wextra -Werror "$project_root/bootstrap/driver.c" \
    "$project_root/bootstrap/host/source.c" "$project_root/bootstrap/host/compiler.c" \
    "$1" "$2" "$3" "$4" -o "$5"
}

compare_diagnostic() {
  compiler=$1
  source=$2
  key=$3
  generation=$4
  diagnostic="$work_dir/diagnostic-$generation-$key"
  if "$compiler" "$source" "$work_dir/rejected.o" >"$diagnostic.out" 2>"$diagnostic.err"; then
    echo "core generation $generation accepted invalid source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/rejected.o"
  if test "$generation" != 0; then
    cmp "$work_dir/diagnostic-0-$key.out" "$diagnostic.out"
    cmp "$work_dir/diagnostic-0-$key.err" "$diagnostic.err"
  fi
}

compare_rejections() {
  compiler=$1
  generation=$2
  for fixture in duplicate_exports uppercase_export export_hyphen empty_call \
      wrong_arity usize_cross_type integer_range unsigned_negative \
      mixed_operator mixed_argument cast_arity lexical_duplicate lexical_scope; do
    compare_diagnostic "$compiler" "$project_root/tests/bootstrap_$fixture.lisp" \
      "$fixture" "$generation"
  done
  for source in "$project_root"/tests/bootstrap_pointer_errors/*.lisp; do
    compare_diagnostic "$compiler" "$source" "pointer-${source##*/}" "$generation"
  done
  for source in "$project_root"/tests/bootstrap_foreign_errors/*.lisp; do
    compare_diagnostic "$compiler" "$source" "foreign-${source##*/}" "$generation"
  done
  for source in "$project_root"/tests/bootstrap_void_errors/*.lisp; do
    compare_diagnostic "$compiler" "$source" "void-${source##*/}" "$generation"
  done
  for source in "$project_root"/tests/bootstrap_query_errors/*.lisp; do
    compare_diagnostic "$compiler" "$source" "query-${source##*/}" "$generation"
  done
  for source in "$project_root"/tests/bootstrap_effect_errors/*.lisp; do
    compare_diagnostic "$compiler" "$source" "effect-${source##*/}" "$generation"
  done
  for fixture in cycle-a missing invalid unterminated; do
    compare_diagnostic "$compiler" "$project_root/tests/include/native/$fixture.lisp" \
      "include-$fixture" "$generation"
  done
  compare_diagnostic "$compiler" "$project_root/examples/basic/add.lisp" \
    unsupported "$generation"
}

# These are generations of the native compiler core, with the same temporary
# C file/path/diagnostic adapter at each generation. They are not complete Stage 1-3 compilers.
"$project_root/pslcc" -c "$project_root/bootstrap/native-core.lisp" \
  -o "$work_dir/core-0.o"
"$project_root/pslcc" -c "$project_root/bootstrap/host/driver.lisp" \
  -o "$work_dir/host-0.o"
"$project_root/pslcc" -c "$project_root/bootstrap/host/source_unit.lisp" \
  -o "$work_dir/source-0.o"
"$project_root/pslcc" -c "$project_root/bootstrap/host/compiler.lisp" \
  -o "$work_dir/driver-0.o"
for generation in 0 1 2; do
  build_driver "$work_dir/core-$generation.o" "$work_dir/host-$generation.o" \
    "$work_dir/source-$generation.o" "$work_dir/driver-$generation.o" \
    "$work_dir/compiler-$generation"
  PATH=/nonexistent "$work_dir/compiler-$generation" \
    "$project_root/bootstrap/native-core.lisp" "$work_dir/core-$((generation + 1)).o"
  PATH=/nonexistent "$work_dir/compiler-$generation" \
    "$project_root/bootstrap/host/driver.lisp" "$work_dir/host-$((generation + 1)).o"
  PATH=/nonexistent "$work_dir/compiler-$generation" \
    "$project_root/bootstrap/host/source_unit.lisp" "$work_dir/source-$((generation + 1)).o"
  PATH=/nonexistent "$work_dir/compiler-$generation" \
    "$project_root/bootstrap/host/compiler.lisp" "$work_dir/driver-$((generation + 1)).o"
  test "$(nm -u "$work_dir/core-$((generation + 1)).o" | wc -l)" -eq 0
  readelf -h "$work_dir/core-$((generation + 1)).o" | grep -q 'REL (Relocatable file)'
  PSL_NATIVE_DRIVER_OBJECT="$work_dir/driver-$generation.o" \
    PSL_NATIVE_SOURCE_OBJECT="$work_dir/source-$generation.o" \
    PSL_NATIVE_HOST_OBJECT="$work_dir/host-$generation.o" \
    PSL_NATIVE_CORE_OBJECT="$work_dir/core-$generation.o" \
    PSL_NATIVE_OBJECT_SNAPSHOT_DIR="$work_dir/objects-$generation" \
    sh "$project_root/tests/bootstrap_native_compiler.sh"
  compare_rejections "$work_dir/compiler-$generation" "$generation"
  if test "$generation" != 0; then
    for object in "$work_dir/objects-0"/*.o; do
      cmp "$object" "$work_dir/objects-$generation/${object##*/}"
    done
  fi
done
cmp "$work_dir/core-1.o" "$work_dir/core-2.o"
cmp "$work_dir/core-2.o" "$work_dir/core-3.o"
cmp "$work_dir/host-1.o" "$work_dir/host-2.o"
cmp "$work_dir/host-2.o" "$work_dir/host-3.o"
cmp "$work_dir/source-1.o" "$work_dir/source-2.o"
cmp "$work_dir/source-2.o" "$work_dir/source-3.o"
cmp "$work_dir/driver-1.o" "$work_dir/driver-2.o"
cmp "$work_dir/driver-2.o" "$work_dir/driver-3.o"
echo 'PSL native core, storage, source loader, and driver generations reproduce identical objects'
