#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
target=${1:-x86_64-linux-gnu}
. "$project_root/tests/bootstrap_target.sh"
select_bootstrap_target

for level in 0 1; do
  "$project_root/pslcc" --target="$target" "-O$level" -c \
    "$project_root/bootstrap/frontend/parser.lisp" -o "$work_dir/parser-O$level.o"
  "$compiler" -Wall -Wextra -Werror \
    "$project_root/tests/harness_bootstrap_parser.c" \
    "$work_dir/parser-O$level.o" -o "$work_dir/parser-O$level$suffix"
  case $target in
    x86_64-windows-gnu)
      run_harness "$work_dir/parser-O$level$suffix" ;;
    *)
      run_harness "$work_dir/parser-O$level$suffix" \
        "$project_root"/examples/*/*.lisp ;;
  esac
done

"$project_root/pslcc" --target="$target" -O1 -c \
  "$project_root/bootstrap/frontend/parser.lisp" -o "$work_dir/repeat.o"
cmp "$work_dir/parser-O1.o" "$work_dir/repeat.o"

echo "PSL bootstrap parser module passed on $target"
