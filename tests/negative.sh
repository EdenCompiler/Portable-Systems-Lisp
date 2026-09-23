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

cat >"$work_dir/unknown-allocation.lisp" <<'SOURCE'
(ffi:import-function "opaque_c" () -> u64)
(defun calls-opaque ()
  (declare (returns u64) (c-export :c))
  (ffi:call opaque_c))
(defun invalid ()
  (declare (returns u64) (c-export :c))
  (without-allocation (calls-opaque)))
SOURCE
expect_error 'WITHOUT-ALLOCATION cannot certify call to calls-opaque' \
  "$work_dir/unknown-allocation.lisp"

cat >"$work_dir/declared-no-allocation.lisp" <<'SOURCE'
(ffi:import-function "known_c" () -> u64 :no-allocation)
(defun valid ()
  (declare (returns u64) (c-export :c))
  (without-allocation (ffi:call known_c)))
SOURCE
"$project_root/pslcc" -c "$work_dir/declared-no-allocation.lisp" \
  -o "$work_dir/declared-no-allocation.o"
nm -u "$work_dir/declared-no-allocation.o" | grep -q known_c

cat >"$work_dir/allocating-region.lisp" <<'SOURCE'
(defun invalid ()
  (declare (returns value) (c-export :c))
  (without-allocation (cons 1 nil)))
SOURCE
if "$project_root/pslcc" --profile=hosted -c \
    "$work_dir/allocating-region.lisp" -o "$work_dir/invalid.o" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  printf 'Expected allocating region failure\n' >&2
  exit 1
fi
grep -q 'WITHOUT-ALLOCATION cannot certify call to psl_rt_cons' \
  "$work_dir/stderr"

cat >"$work_dir/unknown-closure-effect.lisp" <<'SOURCE'
(defun invalid (closure)
  (declare (type value closure) (returns value) (c-export :c))
  (without-allocation (funcall closure 1)))
SOURCE
if "$project_root/pslcc" --profile=hosted -c \
    "$work_dir/unknown-closure-effect.lisp" -o "$work_dir/invalid.o" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  printf 'Expected indirect call effect failure\n' >&2
  exit 1
fi
grep -q 'WITHOUT-ALLOCATION cannot certify call to psl_rt_call_closure' \
  "$work_dir/stderr"

cat >"$work_dir/untraced-managed-field.lisp" <<'SOURCE'
(defstruct/packed bad (item value))
(defun invalid ()
  (declare (returns c-int) (c-export :c))
  0)
SOURCE
if "$project_root/pslcc" --profile=hosted -c \
    "$work_dir/untraced-managed-field.lisp" -o "$work_dir/invalid.o" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  printf 'Expected untraced managed field failure\n' >&2
  exit 1
fi
grep -q 'managed values require a traced runtime object' "$work_dir/stderr"

if "$project_root/pslcc" --profile=freestanding -c \
    "$project_root/examples/hosted/list.lisp" -o "$work_dir/invalid.o" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  printf 'Expected dynamic value profile failure\n' >&2
  exit 1
fi
grep -q 'managed Lisp operations require --profile=hosted' "$work_dir/stderr"

if "$project_root/pslcc" --profile=hosted --target=x86_64-none-elf \
    -c "$project_root/examples/hosted/list.lisp" -o "$work_dir/invalid.o" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  printf 'Expected unavailable hosted runtime target failure\n' >&2
  exit 1
fi
grep -q 'managed Lisp runtime requires a supported hosted target' \
  "$work_dir/stderr"

if "$project_root/pslcc" --target=x86_64-none-elf -c \
    "$project_root/examples/ffi/source_import.lisp" -o "$work_dir/invalid.o" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  printf 'Expected C source target failure\n' >&2
  exit 1
fi
grep -q 'FFI:SOURCE requires a supported hosted target' "$work_dir/stderr"

if "$project_root/pslcc" --target=unknown -c \
    "$project_root/examples/basic/standalone.lisp" -o "$work_dir/invalid.o" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  printf 'Expected unsupported target failure\n' >&2
  exit 1
fi
grep -q 'unsupported target' "$work_dir/stderr"

if "$project_root/pslcc" --target=x86_64-none-elf \
    "$project_root/examples/basic/program.lisp" -o "$work_dir/invalid-program" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  printf 'Expected missing freestanding entry failure\n' >&2
  exit 1
fi
grep -q 'cannot find entry symbol _start' "$work_dir/stderr"
test ! -e "$work_dir/invalid-program"

if "$project_root/pslcc" -c --emit=exe \
    "$project_root/examples/basic/program.lisp" -o "$work_dir/invalid.o" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  printf 'Expected conflicting output options to fail\n' >&2
  exit 1
fi
grep -q -- '-c cannot be combined with --emit' "$work_dir/stderr"
test ! -e "$work_dir/invalid.o"

printf 'PSL negative tests passed\n'
