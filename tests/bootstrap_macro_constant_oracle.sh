#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
sbcl --noinform --script "$project_root/tests/bootstrap_macro_constant_oracle.lisp" >"$work_dir/sbcl.txt"
awk '
  /static const char \*const cl_constant_names\[\]/ { capture=1; next }
  capture && /^};/ { exit }
  capture && /"/ {
    name=$0
    sub(/^[^"]*"/, "", name)
    sub(/".*$/, "", name)
    print name
  }
' "$project_root/tests/harness_bootstrap_macro_let_api.c" | LC_ALL=C sort >"$work_dir/fixture.txt"
test "$(wc -l <"$work_dir/sbcl.txt")" -eq 62
cmp "$work_dir/sbcl.txt" "$work_dir/fixture.txt"
echo "SBCL COMMON-LISP external CONSTANTP catalogue matches the 62-name fixture"
