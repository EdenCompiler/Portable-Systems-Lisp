#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
compiler=${PSL_NATIVE_COMPILER:-$project_root/build/pslcc-native}
host_cc=${CC:-cc}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

if test ! -x "$compiler"; then
  echo "native compiler not found: $compiler (run make native first)" >&2
  exit 2
fi

source=$project_root/tests/bootstrap_symbols.lisp
harness=$project_root/tests/harness_bootstrap_symbols.c
"$compiler" "$source" "$work_dir/symbols.o"
"$host_cc" -Wall -Wextra -Werror "$harness" "$work_dir/symbols.o" \
  -o "$work_dir/symbols"
"$work_dir/symbols"
"$compiler" "$source" "$work_dir/symbols-repeat.o"
cmp "$work_dir/symbols.o" "$work_dir/symbols-repeat.o"

for source in "$project_root"/tests/bootstrap_symbol_errors/*.lisp; do
  if "$compiler" "$source" "$work_dir/invalid.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native compiler accepted invalid symbol source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid.o"
done

echo 'native symbol identity checks passed'
