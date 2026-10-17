#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
if test "${1:-}" = arena || test "${1:-}" = atoms; then
  # Preserve the original one-component seed invocation for local debugging.
  native_compiler=$project_root/pslcc
  components=$1
  target=${2:-x86_64-linux-gnu}
else
  native_compiler=${1:-$project_root/pslcc}
  target=${2:-x86_64-linux-gnu}
  components='arena atoms'
fi

. "$project_root/tests/bootstrap_target.sh"
select_bootstrap_target
target_cc=$compiler

for component in $components; do
  case $component in
    arena) source_file="$project_root/bootstrap/arena.lisp" ;;
    atoms) source_file="$project_root/bootstrap/frontend/atoms.lisp" ;;
    *) echo "unsupported bootstrap component: $component" >&2; exit 2 ;;
  esac
  for level in 0 1; do
    "$native_compiler" --target="$target" "-O$level" -c \
      "$source_file" -o "$work_dir/$component-O$level.o"
    "$target_cc" -Wall -Wextra -Werror \
      "$project_root/tests/harness_bootstrap_$component.c" \
      "$work_dir/$component-O$level.o" \
      -o "$work_dir/$component-O$level$suffix"
    run_harness "$work_dir/$component-O$level$suffix"
  done

  "$native_compiler" --target="$target" -O1 -c \
    "$source_file" -o "$work_dir/repeat.o"
  cmp "$work_dir/$component-O1.o" "$work_dir/repeat.o"
  echo "PSL bootstrap $component module passed on $target"
done
