#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
project_root=$root
. "$root/tests/bootstrap_test_runner.sh"
bootstrap_test_runner_init "${2:-x86_64-linux-gnu}"
compiler=${1:-$root/build/pslcc-native}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

compare_case() {
  name=$1
  expected_status=$2
  shift 2
  set +e
  run_compiler_host "$compiler" "$@" >"$work/native.out" 2>"$work/native.err"
  native_status=$?
  "$root/pslcc" "$@" >"$work/stage0.out" 2>"$work/stage0.err"
  stage0_status=$?
  set -e
  test "$native_status" -eq "$expected_status" || {
    echo "$name: native status $native_status, expected $expected_status" >&2
    exit 1
  }
  test "$stage0_status" -eq "$expected_status" || {
    echo "$name: Stage 0 status $stage0_status, expected $expected_status" >&2
    exit 1
  }
  if [ "$name" = help ] || [ "$name" = short-help ]; then
    grep -q '^Usage: pslcc-native ' "$work/native.out"
    grep -q 'Targets: x86_64-linux-gnu, aarch64-linux-gnu, riscv64-linux-gnu, x86_64-windows-gnu$' "$work/native.out"
    grep -q -- '--dump-ir=hir|ssa|lir|all' "$work/native.out"
    test ! -s "$work/native.err"
  else
    test "$(sed -n '1p' "$work/native.err")" = "$(sed -n '1p' "$work/stage0.err")"
    grep -q '^Usage: pslcc-native ' "$work/native.err"
  fi
}

compare_case help 0 --help
compare_case short-help 0 -h
compare_case bare 1
compare_case unknown-option 1 --unknown
compare_case missing-value 1 -o
compare_case extra-argument 1 "$root/examples/basic/standalone.lisp" \
  -o "$work/output" extra.lisp
compare_case compile-emit-conflict 1 "$root/examples/basic/standalone.lisp" \
  -o "$work/output" -c --emit=exe
compare_case compile-input-conflict 1 "$root/examples/basic/standalone.lisp" \
  -o "$work/output" -c --link-input=unused.o
printf 'Native CLI help and parse diagnostics match Stage 0\n'
