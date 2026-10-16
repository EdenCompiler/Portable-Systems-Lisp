#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
compiler=${1:-$project_root/build/pslcc-native}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
source=$work_dir/large-startup.lisp
functions=7000
{
  cat "$project_root/tests/bootstrap_cli_large_startup.lisp" | sed '/^(defun large_6999 /,$d'
  index=0
  while test "$index" -lt "$functions"; do
    printf '(defun large_%s () (declare (returns u64)) %s)\n' "$index" "$index"
    index=$((index + 1))
  done
  cat "$project_root/tests/bootstrap_cli_large_startup.lisp" | sed -n '/^(defun main /,$p'
} >"$source"
cc -std=c11 -O2 -ffreestanding -fno-pie -fno-stack-protector \
  -fno-unwind-tables -fno-asynchronous-unwind-tables -Wall -Wextra -Werror \
  -c "$project_root/tests/harness_cli_large_startup.c" -o "$work_dir/caller.o"

for level in 0 1; do
  for mode in native seed; do
    executable=$work_dir/large-$mode-O$level
    if test "$mode" = native; then
      "$compiler" "-O$level" --profile=freestanding "$source" \
        --target=x86_64-none-elf --startup=linux-exit \
        --link-input="$work_dir/caller.o" -o "$executable"
    else
      "$project_root/pslcc" "-O$level" --profile=freestanding "$source" \
        --target=x86_64-none-elf --startup=linux-exit \
        --link-input="$work_dir/caller.o" -o "$executable"
    fi
    test -z "$(nm -u "$executable")"
    test "$(wc -c <"$executable")" -gt 65536
    readelf -h "$executable" | grep -q 'Type:.*EXEC (Executable file)'
    readelf -l "$executable" | grep -q 'R E'
    readelf -l "$executable" | grep -q 'RW '
    (ulimit -s 128; "$executable")
  done
done

private_output=$work_dir/private-main
printf 'preserve private-main output\n' >"$private_output"
cp "$private_output" "$work_dir/private-expected"
for mode in native seed; do
  if test "$mode" = native; then
    if "$compiler" --profile=freestanding \
      "$project_root/tests/bootstrap_cli_private_main.lisp" \
      --target=x86_64-none-elf --startup=linux-exit -o "$private_output" \
      >"$work_dir/private-$mode.out" 2>"$work_dir/private-$mode.err"; then
      echo 'native accepted non-exported main for separate startup' >&2
      exit 1
    fi
  else
    if "$project_root/pslcc" --profile=freestanding \
      "$project_root/tests/bootstrap_cli_private_main.lisp" \
      --target=x86_64-none-elf --startup=linux-exit -o "$private_output" \
      >"$work_dir/private-$mode.out" 2>"$work_dir/private-$mode.err"; then
      echo 'Stage 0 accepted non-exported main for separate startup' >&2
      exit 1
    fi
  fi
  cmp "$work_dir/private-expected" "$private_output"
done

printf 'Large freestanding startup rotates >64 KiB code, calls internal functions, relocates imported C data and runs with a 128 KiB stack; private main is rejected\n'
