#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
source=$project_root/tests/bootstrap_answer.lisp
c_harness=$project_root/tests/harness_bootstrap_answer.c

for target in x86_64-none-elf riscv64-none-elf; do
  case $target in
    x86_64-none-elf)
      hosted_target=x86_64-linux-gnu
      target_cc=${CC:-cc}
      runner=direct ;;
    riscv64-none-elf)
      hosted_target=riscv64-linux-gnu
      target_cc=${RISCV64_CC:-riscv64-linux-gnu-gcc}
      runner=riscv64 ;;
  esac
  bootstrap_test_runner_init "$hosted_target"
  command -v "$target_cc" >/dev/null 2>&1 || {
    echo "required none-target ABI caller compiler is unavailable: $target_cc" >&2
    exit 2
  }
  if [ "$runner" = riscv64 ]; then
    command -v qemu-riscv64 >/dev/null 2>&1 || {
      echo 'required RISC-V runner is unavailable: qemu-riscv64' >&2
      exit 2
    }
  fi
  for level in 0 1; do
    native_object=$work_dir/native-$target-O$level.o
    seed_object=$work_dir/seed-$target-O$level.o
    native_hosted_object=$work_dir/native-$hosted_target-O$level.o
    seed_hosted_object=$work_dir/seed-$hosted_target-O$level.o
    run_compiler_host "$compiler" "-O$level" -c "$source" --target="$target" \
      -o "$native_object"
    "$project_root/pslcc" "-O$level" -c "$source" --target "$target" \
      -o "$seed_object"
    run_compiler_host "$compiler" "-O$level" -c "$source" --target="$hosted_target" \
      -o "$native_hosted_object"
    "$project_root/pslcc" "-O$level" -c "$source" --target "$hosted_target" \
      -o "$seed_hosted_object"
    cmp "$native_object" "$native_hosted_object"
    cmp "$seed_object" "$seed_hosted_object"
    for object in "$native_object" "$seed_object"; do
      readelf -h "$object" >"$work_dir/header.txt"
      grep -q 'Class:.*ELF64' "$work_dir/header.txt"
      case $target in
        x86_64-none-elf)
          grep -q 'Machine:.*Advanced Micro Devices X86-64' "$work_dir/header.txt"
          grep -q 'Flags:.*0x0' "$work_dir/header.txt"
          ;;
        riscv64-none-elf)
          grep -q 'Machine:.*RISC-V' "$work_dir/header.txt"
          grep -q 'Flags:.*0x4' "$work_dir/header.txt"
          ;;
      esac
    done
    for object in "$native_object" "$seed_object"; do
      executable=$work_dir/answer-$target-O$level
      "$target_cc" -std=c11 -Wall -Wextra -Werror "$c_harness" \
        "$object" -o "$executable"
      run_target "$executable"
    done
  done

  # Both call validators and the combined code/data writer must use architecture,
  # independently of the OS-bearing target ID.
  for level in 0 1; do
    calls_source=$project_root/tests/bootstrap_none_calls_data.lisp
    for mode in native seed; do
      for output_target in "$target" "$hosted_target"; do
        object=$work_dir/$mode-$output_target-calls.o
        if test "$mode" = native; then
          run_compiler_host "$compiler" "-O$level" -c "$calls_source" \
            --target="$output_target" -o "$object"
        else
          "$project_root/pslcc" "-O$level" -c "$calls_source" \
            --target="$output_target" -o "$object"
        fi
      done
      cmp "$work_dir/$mode-$target-calls.o" "$work_dir/$mode-$hosted_target-calls.o"
      readelf -r "$work_dir/$mode-$target-calls.o" > "$work_dir/relocations"
      grep -q none_adjust "$work_dir/relocations"
      grep -q none_bias "$work_dir/relocations"
      for c_level in 0 2; do
        "$target_cc" "-O$c_level" -std=c11 -Wall -Wextra -Werror \
          "$project_root/tests/harness_bootstrap_none_calls_data.c" \
          "$work_dir/$mode-$target-calls.o" -o "$work_dir/calls"
        run_target "$work_dir/calls"
      done
    done
  done

  printf 'preserve an existing output\n' >"$work_dir/preserved"
  cp "$work_dir/preserved" "$work_dir/expected"
  cat >"$work_dir/value-result.lisp" <<'EOF'
(defun managed () (declare (returns value) (c-export :c)) nil)
EOF
  cat >"$work_dir/value-identity.lisp" <<'EOF'
(defun value-id (x) (declare (type value x) (returns value) (c-export :c)) x)
EOF
  cat >"$work_dir/managed-leaf.lisp" <<'EOF'
(defun managed () (declare (returns value) (c-export :c)) (box-fixnum 42))
EOF
  cat >"$work_dir/hosted-scalar.lisp" <<'EOF'
(defun scalar () (declare (returns u64) (c-export :c)) 42)
EOF
  "$project_root/pslcc" --profile=hosted --target="$target" -c \
    "$work_dir/hosted-scalar.lisp" -o "$work_dir/stage0-hosted-scalar.o"
  run_compiler_host "$compiler" --profile=hosted --target="$target" -c \
    "$work_dir/hosted-scalar.lisp" -o "$work_dir/native-hosted-scalar.o"
  for managed_source in "$work_dir/value-result.lisp" \
      "$work_dir/value-identity.lisp" "$work_dir/managed-leaf.lisp" \
      "$project_root/examples/hosted/list.lisp"; do
    if "$project_root/pslcc" --profile=hosted --target="$target" -c \
        "$managed_source" -o "$work_dir/stage0-managed-$target.o" \
        >"$work_dir/stdout" 2>"$work_dir/stderr"; then
      echo "Stage 0 accepted hosted managed code for $target: $managed_source" >&2
      exit 1
    else
      test "$?" -eq 1
    fi
    grep -q 'managed Lisp runtime requires a supported hosted target' \
      "$work_dir/stderr"
    test ! -e "$work_dir/stage0-managed-$target.o"

    if run_compiler_host "$compiler" --profile=hosted --target="$target" -c \
        "$managed_source" -o "$work_dir/preserved" \
        >"$work_dir/stdout" 2>"$work_dir/stderr"; then
      echo "Native compiler accepted hosted managed code for $target: $managed_source" >&2
      exit 1
    else
      test "$?" -eq 1
    fi
    grep -q 'managed Lisp runtime requires a supported hosted target' \
      "$work_dir/stderr"
    test ! -s "$work_dir/stdout"
    cmp "$work_dir/expected" "$work_dir/preserved"
  done

  for kind in exe static shared; do
    if run_compiler_host "$compiler" --emit="$kind" "$source" -o "$work_dir/preserved" \
        --target="$target" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
      echo "native CLI linked unsupported $target $kind output" >&2
      exit 1
    else
      test "$?" -eq 1
    fi
    cmp "$work_dir/expected" "$work_dir/preserved"
    grep -q 'none-elf targets currently support -c object output only' \
      "$work_dir/stderr"
    test ! -s "$work_dir/stdout"
  done
done

run_compiler_host "$compiler" --help >"$work_dir/help"
grep -q 'x86_64-none-elf, riscv64-none-elf' "$work_dir/help"
grep -q 'none-elf targets currently support -c object output only' \
  "$work_dir/help"
printf 'Native none-ELF object targets match Stage 0; unsupported links preserve outputs\n'
