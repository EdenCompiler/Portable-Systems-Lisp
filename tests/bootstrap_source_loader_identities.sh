#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
fixtures=$project_root/tests/source_loader_identities

# C-source paths are relative to their declaring included file, and included
# package selection affects the following source. Repeated includes deduplicate.
for level in 0 1; do
  run_compiler_host "$compiler" "-O$level" --target="$target" -c \
    "$fixtures/entry.lisp" -o "$work_dir/native.o"
  run_compiler_host "$compiler" "-O$level" --target="$target" -c \
    "$fixtures/entry.lisp" -o "$work_dir/repeat.o"
  cmp "$work_dir/native.o" "$work_dir/repeat.o"
  "$project_root/pslcc" "-O$level" --target="$target" -c \
    "$fixtures/entry.lisp" -o "$work_dir/seed.o"
  for version in native seed; do
    for c_level in 0 2; do
      "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
        "$project_root/tests/harness_source_loader_identities.c" \
        "$work_dir/$version.o" -o "$work_dir/check$target_suffix"
      run_target "$work_dir/check$target_suffix"
    done
  done
  for name in shadowed malformed unknown-package cycle missing package-order; do
    printf 'preserve existing output\n' >"$work_dir/preserved.o"
    cp "$work_dir/preserved.o" "$work_dir/expected"
    for version in native seed; do
      if test "$version" = native; then
        if run_compiler_host "$compiler" "-O$level" --target="$target" -c \
          "$fixtures/$name.lisp" -o "$work_dir/preserved.o" \
          >"$work_dir/stdout" 2>"$work_dir/stderr"; then
          echo "native accepted invalid directive identity: $name" >&2; exit 1
        else
          test "$?" -eq 1
        fi
      elif "$project_root/pslcc" "-O$level" --target="$target" -c \
        "$fixtures/$name.lisp" -o "$work_dir/preserved.o" \
        >"$work_dir/stdout" 2>"$work_dir/stderr"; then
        echo "Stage 0 accepted invalid directive identity: $name" >&2; exit 1
      else
        test "$?" -eq 1
      fi
      cmp "$work_dir/expected" "$work_dir/preserved.o"
      test -s "$work_dir/stderr"
    done
  done
done

# The second included file forces growth after the first file has populated
# reader tables. Later alias lookups and calls must retain the earlier IDs.
cat >"$work_dir/growth.lisp" <<'EOF_GROWTH'
(defpackage #:loader-growth (:use #:cl) (:import-from #:psl #:include) (:export #:include))
(in-package #:loader-growth)
(loader-growth:include "many-one.lisp")
(loader-growth:|INCLUDE| "many-two.lisp")
(defun loader_growth_answer ()
  (declare (psl:returns psl:c-int) (psl:c-export :c))
  (psl:wrap- (loader_many_699) 657))
EOF_GROWTH
index=0
while test "$index" -lt 700; do
  if test "$index" -lt 300; then part=one; else part=two; fi
  printf '(defun loader_many_%s () (declare (psl:returns psl:c-int)) %s)\n' \
    "$index" "$index" >>"$work_dir/many-$part.lisp"
  index=$((index + 1))
done
cat >"$work_dir/growth.c" <<'EOF_C'
extern int loader_growth_answer(void);
int main(void) { return loader_growth_answer() == 42 ? 0 : 1; }
EOF_C
for level in 0 1; do
  run_compiler_host "$compiler" "-O$level" --target="$target" -c \
    "$work_dir/growth.lisp" -o "$work_dir/native.o"
  run_compiler_host "$compiler" "-O$level" --target="$target" -c \
    "$work_dir/growth.lisp" -o "$work_dir/repeat.o"
  cmp "$work_dir/native.o" "$work_dir/repeat.o"
  "$project_root/pslcc" "-O$level" --target="$target" -c \
    "$work_dir/growth.lisp" -o "$work_dir/seed.o"
  for version in native seed; do
    for c_level in 0 2; do
      "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
        "$work_dir/growth.c" "$work_dir/$version.o" \
        -o "$work_dir/growth$target_suffix"
      run_target "$work_dir/growth$target_suffix"
    done
  done
done
printf 'Source-loader package identities, C paths, ordered packages, typed table growth and output preservation passed (%s)\n' "$target"
