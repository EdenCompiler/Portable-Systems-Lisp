#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

expect_error() {
  expected=$1
  source=$2
  if "$project_root/pslcc" -c "$source" -o "$work_dir/invalid.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    printf 'Expected compilation failure: %s\n' "$source" >&2
    exit 1
  fi
  if ! grep -q "$expected" "$work_dir/stderr"; then
    cat "$work_dir/stderr" >&2
    printf 'Missing expected diagnostic: %s\n' "$expected" >&2
    exit 1
  fi
  if ! grep -Eq "${source}:[0-9]+:[0-9]+" "$work_dir/stderr"; then
    cat "$work_dir/stderr" >&2
    printf 'Missing source location: %s\n' "$source" >&2
    exit 1
  fi
  if test -e "$work_dir/invalid.o"; then
    printf 'Compiler created an object after failure: %s\n' "$source" >&2
    exit 1
  fi
}

cat >"$work_dir/overflow.lisp" <<'SOURCE'
(defun overflow ()
  (declare (returns u8) (c-export :c))
  256)
SOURCE
expect_error 'does not fit' "$work_dir/overflow.lisp"

cat >"$work_dir/unqualified-plus.lisp" <<'SOURCE'
(defun invalid (x)
  (declare (type u64 x) (returns u64) (c-export :c))
  (+ x 1))
SOURCE
expect_error 'unsupported form' "$work_dir/unqualified-plus.lisp"

cat >"$work_dir/early-macro.lisp" <<'SOURCE'
(defun invalid (x)
  (declare (type u64 x) (returns u64) (c-export :c))
  (later x))
(defmacro later (x) `(wrap+ ,x 1))
SOURCE
expect_error 'unsupported form' "$work_dir/early-macro.lisp"

cat >"$work_dir/const-store.lisp" <<'SOURCE'
(defun invalid (p)
  (declare (type (ptr u8 :const) p) (returns u8) (c-export :c))
  (store p 1))
SOURCE
expect_error 'const pointer' "$work_dir/const-store.lisp"

cat >"$work_dir/duplicate-field.lisp" <<'SOURCE'
(defstruct/packed bad (x u8) (x u16))
(defun invalid ()
  (declare (returns usize) (c-export :c))
  (sizeof 'bad))
SOURCE
expect_error 'duplicate field' "$work_dir/duplicate-field.lisp"

cat >"$work_dir/oversized-aggregate.lisp" <<'SOURCE'
(defcstruct big (a u64) (b u64) (c u64))
(defun invalid (value)
  (declare (type big value) (returns big) (c-export :c))
  value)
SOURCE
expect_error 'scalar C layout of at most 16 bytes' \
  "$work_dir/oversized-aggregate.lisp"

cat >"$work_dir/packed-aggregate.lisp" <<'SOURCE'
(defstruct/packed mixed (a u8) (b u64))
(defun invalid (value)
  (declare (type mixed value) (returns mixed) (c-export :c))
  value)
SOURCE
expect_error 'scalar C layout of at most 16 bytes' \
  "$work_dir/packed-aggregate.lisp"

cat >"$work_dir/direct-c-call.lisp" <<'SOURCE'
(ffi:import-function "multiply_c" ((x u64)) -> u64)
(defun invalid (x)
  (declare (type u64 x) (returns u64) (c-export :c))
  (multiply_c x))
SOURCE
expect_error 'FFI:CALL' "$work_dir/direct-c-call.lisp"

cat >"$work_dir/missing-c-source.lisp" <<'SOURCE'
(ffi:source "missing.c")
(defun valid ()
  (declare (returns u64) (c-export :c))
  42)
SOURCE
expect_error 'file does not exist' "$work_dir/missing-c-source.lisp"

cat >"$work_dir/reserved-macro.lisp" <<'SOURCE'
(defmacro wrap+ (x y) `(cl:+ ,x ,y))
(defun valid ()
  (declare (returns u64) (c-export :c))
  42)
SOURCE
expect_error 'conflicts with a Common Lisp or compiler name' "$work_dir/reserved-macro.lisp"

if "$project_root/pslcc" --target=x86_64-none-elf -c \
    "$project_root/examples/ffi_source.lisp" -o "$work_dir/invalid.o" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  printf 'Expected C source target failure\n' >&2
  exit 1
fi
grep -q 'requires x86_64-linux-gnu' "$work_dir/stderr"

if "$project_root/pslcc" --target=unknown -c \
    "$project_root/examples/standalone.lisp" -o "$work_dir/invalid.o" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  printf 'Expected unsupported target failure\n' >&2
  exit 1
fi
grep -q 'unsupported target' "$work_dir/stderr"

if "$project_root/pslcc" --target=x86_64-none-elf \
    "$project_root/examples/program.lisp" -o "$work_dir/invalid-program" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  printf 'Expected non-native linking failure\n' >&2
  exit 1
fi
grep -q 'linking currently requires x86_64-linux-gnu' "$work_dir/stderr"
test ! -e "$work_dir/invalid-program"

if "$project_root/pslcc" -c --emit=exe \
    "$project_root/examples/program.lisp" -o "$work_dir/invalid.o" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  printf 'Expected conflicting output options to fail\n' >&2
  exit 1
fi
grep -q -- '-c cannot be combined with --emit' "$work_dir/stderr"
test ! -e "$work_dir/invalid.o"

printf 'PSL negative tests passed\n'
