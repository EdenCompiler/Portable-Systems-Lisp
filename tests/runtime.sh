#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

for source in "$project_root"/runtime/*.c; do
  if [ "${source##*/}" = platform_windows.c ]; then
    continue
  fi
  name=$(basename "${source%.c}")
  cc -std=c11 -Wall -Wextra -Werror -O0 -fPIC -pthread \
    -c "$source" -o "$work_dir/$name.o"
done

ar rcsD "$work_dir/libpsl-runtime.a" "$work_dir"/*.o
cc -std=c11 -Wall -Wextra -Werror -O0 -pthread \
  "$project_root/tests/runtime.c" "$work_dir/libpsl-runtime.a" \
  -o "$work_dir/runtime-test"
"$work_dir/runtime-test"
