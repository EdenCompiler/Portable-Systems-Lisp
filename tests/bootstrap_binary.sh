#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
target=${1:-x86_64-linux-gnu}
. "$project_root/tests/bootstrap_target.sh"
select_bootstrap_target

PSL_BOOTSTRAP_REFERENCE="$work_dir/reference.bin" \
  sbcl --noinform --script "$project_root/tests/reference_bootstrap_binary.lisp"

for level in 0 1; do
  "$project_root/pslcc" --target="$target" "-O$level" -c \
    "$project_root/bootstrap/binary.lisp" -o "$work_dir/binary-O$level.o"
  case $target in
    x86_64-windows-gnu)
      x86_64-w64-mingw32-nm -g "$work_dir/binary-O$level.o" ;;
    *)
      nm -g "$work_dir/binary-O$level.o" ;;
  esac > "$work_dir/symbols-O$level"
  if grep -E ' (T|t) (room_for|emit_byte_unchecked|emit_integer_steps|patch_integer_steps)$' \
      "$work_dir/symbols-O$level"; then
    echo 'internal bootstrap helper is publicly visible' >&2
    exit 1
  fi
  "$compiler" -Wall -Wextra -Werror \
    "$project_root/tests/harness_bootstrap_binary.c" \
    "$work_dir/binary-O$level.o" -o "$work_dir/binary-O$level$suffix"
  run_harness "$work_dir/binary-O$level$suffix" \
    > "$work_dir/native-O$level.bin"
  cmp "$work_dir/reference.bin" "$work_dir/native-O$level.bin"
done

"$project_root/pslcc" --target="$target" -O1 -c \
  "$project_root/bootstrap/binary.lisp" \
  -o "$work_dir/repeat.o"
cmp "$work_dir/binary-O1.o" "$work_dir/repeat.o"

echo "PSL bootstrap binary module passed on $target"
