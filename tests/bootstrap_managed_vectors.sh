#!/bin/sh
set -eu
ulimit -c 0
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
target=${1:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
case $target in
  x86_64-windows-gnu) platform=windows; allocator_flags= ;;
  *) platform=linux
     allocator_flags='-DPSL_VECTOR_ALLOC_WRAPPERS -Wl,--wrap=malloc -Wl,--wrap=calloc -Wl,--wrap=realloc' ;;
esac

"$target_cc" -O0 -Wall -Wextra -Werror -c \
  "$project_root/runtime/platform_$platform.c" -o "$work_dir/platform.o"
for level in 0 2; do
  "$target_cc" "-O$level" -std=c11 -Wall -Wextra -Werror \
    $allocator_flags "$project_root/tests/runtime_precise_vectors.c" \
    "$project_root/runtime/value.c" "$project_root/runtime/cons.c" \
    "$project_root/runtime/string.c" "$project_root/runtime/closure.c" \
    "$project_root/runtime/vector.c" "$project_root/runtime/gc.c" \
    "$project_root/runtime/startup.c" "$work_dir/platform.o" \
    -o "$work_dir/runtime$target_suffix"
  run_target "$work_dir/runtime$target_suffix"
  for invalid in bounds set-bounds wrong-kind overflow; do
    if run_target "$work_dir/runtime$target_suffix" "$invalid" \
        >"$work_dir/invalid.log" 2>&1; then
      echo "VALUE vector runtime accepted invalid operation: $invalid" >&2
      exit 1
    fi
  done
done

"$target_cc" -O2 -std=c11 -Wall -Wextra -Werror -c \
  "$project_root/tests/harness_bootstrap_managed_vectors.c" \
  -o "$work_dir/vectors-harness.o"
for level in 0 1; do
  source=$project_root/tests/bootstrap_managed_vectors.lisp
  "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted \
    -c "$source" -o "$work_dir/native.o"
  "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted \
    -c "$source" -o "$work_dir/repeat.o"
  cmp "$work_dir/native.o" "$work_dir/repeat.o"
  "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted \
    --link-input="$work_dir/vectors-harness.o" "$source" \
    -o "$work_dir/check$target_suffix"
  run_target "$work_dir/check$target_suffix"
done
printf 'Managed VALUE vectors passed (%s)\n' "$target"
