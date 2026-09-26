#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
component=${1:-}
target=${2:-x86_64-linux-gnu}

case $component in
  arena) source_file="$project_root/bootstrap/arena.lisp" ;;
  atoms) source_file="$project_root/bootstrap/frontend/atoms.lisp" ;;
  *) echo 'usage: bootstrap_component.sh arena|atoms [TARGET]' >&2; exit 2 ;;
esac

. "$project_root/tests/bootstrap_target.sh"
select_bootstrap_target

for level in 0 1; do
  "$project_root/pslcc" --target="$target" "-O$level" -c \
    "$source_file" \
    -o "$work_dir/$component-O$level.o"
  "$compiler" -Wall -Wextra -Werror \
    "$project_root/tests/harness_bootstrap_$component.c" \
    "$work_dir/$component-O$level.o" \
    -o "$work_dir/$component-O$level$suffix"
  run_harness "$work_dir/$component-O$level$suffix"
done

"$project_root/pslcc" --target="$target" -O1 -c \
  "$source_file" -o "$work_dir/repeat.o"
cmp "$work_dir/$component-O1.o" "$work_dir/repeat.o"

echo "PSL bootstrap $component module passed on $target"
