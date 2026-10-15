#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
case $target in x86_64-windows-gnu) platform=windows ;; *) platform=linux ;; esac
"$target_cc" -O0 -std=c11 -Wall -Wextra -Werror -c \
  "$project_root/runtime/platform_$platform.c" -o "$work_dir/platform.o"
for level in 0 1; do
  for fixture in source_identities source_identities_managed; do
    source=$project_root/tests/$fixture.lisp
    run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted \
      "$source" "$work_dir/native.o"
    run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted \
      "$source" "$work_dir/repeat.o"
    cmp "$work_dir/native.o" "$work_dir/repeat.o"
    "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted \
      -c "$source" -o "$work_dir/seed.o"
    for version in native seed; do
      for c_level in 0 2; do
        if test "$fixture" = source_identities; then
          "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
            "$project_root/tests/harness_source_identities.c" "$work_dir/$version.o" \
            -o "$work_dir/check$target_suffix"
        else
          "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
            "$work_dir/$version.o" "$work_dir/platform.o" \
            "$project_root/runtime/value.c" "$project_root/runtime/cons.c" \
            "$project_root/runtime/closure.c" "$project_root/runtime/values.c" \
            "$project_root/runtime/gc.c" "$project_root/runtime/startup.c" \
            -o "$work_dir/check$target_suffix"
        fi
        run_target "$work_dir/check$target_suffix"
      done
    done
  done
  for source in "$project_root"/tests/bootstrap_reader_identity_errors/*.lisp; do
    for version in native seed; do
      rm -f "$work_dir/rejected.o"
      if test "$version" = native; then
        if run_compiler_host "$compiler" "-O$level" --target="$target" \
          "$source" "$work_dir/rejected.o" >"$work_dir/error" 2>&1; then
          echo 'Native compiler aliased a distinct source identity' >&2; exit 1
        else
          test "$?" -eq 1
        fi
      elif "$project_root/pslcc" "-O$level" --target="$target" \
        -c "$source" -o "$work_dir/rejected.o" >"$work_dir/error" 2>&1; then
        echo 'Stage 0 aliased a distinct source identity' >&2; exit 1
      else
        test "$?" -eq 1
      fi
      test ! -e "$work_dir/rejected.o"
      test -s "$work_dir/error"
    done
  done
done
printf 'Native and Stage 0 escaped lexical identities, captures and values passed (%s)\n' "$target"
