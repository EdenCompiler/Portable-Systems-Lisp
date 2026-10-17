#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
core=${1:-$project_root/build/native-core.o}
source=${2:-$project_root/build/native-source.o}
input=${3:-$project_root/build/native-input.o}
path=${4:-$project_root/build/native-path.o}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
cat >"$work_dir/growth.lisp" <<'EOF_SOURCE'
(defpackage #:allocation-loader (:use #:cl) (:import-from #:psl #:include))
(in-package #:allocation-loader)
(include "first.lisp")
(include "second.lisp")
EOF_SOURCE
index=0
while test "$index" -lt 200; do
  if test "$index" -lt 30; then part=first; else part=second; fi
  printf '(defun allocation_function_%s () (declare (psl:returns psl:c-int)) %s)\n' \
    "$index" "$index" >>"$work_dir/$part.lisp"
  index=$((index + 1))
done
for level in 0 2; do
  cc "-O$level" -std=c11 -Wall -Wextra -Werror -pthread \
    "$project_root/tests/harness_source_loader_allocations.c" \
    "$core" "$source" "$input" "$path" \
    "$project_root/runtime/value.c" "$project_root/runtime/cons.c" \
    "$project_root/runtime/string.c" "$project_root/runtime/symbol.c" \
    "$project_root/runtime/package.c" "$project_root/runtime/closure.c" \
    "$project_root/runtime/vector.c" "$project_root/runtime/values.c" \
    "$project_root/runtime/gc.c" "$project_root/runtime/startup.c" \
    "$project_root/runtime/platform_linux.c" \
    -Wl,--wrap=malloc -Wl,--wrap=calloc -Wl,--wrap=realloc -Wl,--wrap=free \
    -o "$work_dir/check"
  "$work_dir/check" "$project_root/tests/source_loader_identities/entry.lisp" \
    "$work_dir/growth.lisp"
done
