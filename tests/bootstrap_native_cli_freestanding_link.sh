#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
compiler=${1:-$project_root/build/pslcc-native}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
mkdir -p "$work_dir/maps"
cross_root=${PSL_CROSS_ROOT:-$project_root/build/m8-cross-tools}
PATH="$cross_root/bin:$cross_root/usr/bin:$PATH"
LD_LIBRARY_PATH="$cross_root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH LD_LIBRARY_PATH

for level in 0 1; do
  native_x86=$work_dir/native-x86-O$level
  native_x86_map=$work_dir/maps/native-x86-O$level.map
  stage0_x86=$work_dir/stage0-x86-O$level
  "$compiler" "-O$level" --emit=exe --profile=freestanding \
    --target=x86_64-none-elf --startup=linux-exit \
    "$project_root/tests/bootstrap_cli_link_freestanding_exit.lisp" \
    -o "$native_x86" --map="$native_x86_map"
  "$project_root/pslcc" "-O$level" --emit=exe --profile=freestanding \
    --target=x86_64-none-elf --startup=linux-exit \
    "$project_root/tests/bootstrap_cli_link_freestanding_exit.lisp" \
    -o "$stage0_x86"
  "$native_x86"
  "$stage0_x86"
  readelf -h "$native_x86" >"$work_dir/x86-header"
  grep -q 'Type:.*EXEC' "$work_dir/x86-header"
  grep -q 'Machine:.*Advanced Micro Devices X86-64' "$work_dir/x86-header"
  nm "$native_x86" | grep -q ' _start$'
  test -s "$native_x86_map"

  native_rv=$work_dir/native-rv-O$level
  native_rv_map=$work_dir/maps/native-rv-O$level.map
  stage0_rv=$work_dir/stage0-rv-O$level
  "$compiler" "-O$level" --emit=exe --profile=freestanding \
    --target=riscv64-none-elf --startup=qemu-virt \
    "$project_root/examples/freestanding/virt_uart.lisp" \
    -o "$native_rv" --map="$native_rv_map"
  "$project_root/pslcc" "-O$level" --emit=exe --profile=freestanding \
    --target=riscv64-none-elf --startup=qemu-virt \
    "$project_root/examples/freestanding/virt_uart.lisp" \
    -o "$stage0_rv"
  for executable in "$native_rv" "$stage0_rv"; do
    readelf -h "$executable" >"$work_dir/rv-header"
    grep -q 'Type:.*EXEC' "$work_dir/rv-header"
    grep -q 'Machine:.*RISC-V' "$work_dir/rv-header"
    grep -q 'Entry point address: *0x80000000' "$work_dir/rv-header"
    timeout 20 qemu-system-riscv64 -machine virt -nographic -monitor none \
      -bios none -kernel "$executable" >"$work_dir/rv-output" 2>"$work_dir/rv-error"
    grep -q '^P' "$work_dir/rv-output"
  done
  test -s "$native_rv_map"
done

# Generated startup must survive both syntax and IR-buffer retries.
expr=1
i=0
while test "$i" -lt 8; do expr="(double-syntax $expr)"; i=$((i + 1)); done
cat >"$work_dir/retry-startup.lisp" <<EOF_RETRY
(defmacro double-syntax (x) (list 'wrap+ x x))
(defun main () (declare (returns c-int) (c-export :c)) (wrap- $expr 256))
EOF_RETRY
for target in x86_64-none-elf riscv64-none-elf; do
  case $target in
    x86_64-none-elf) startup=linux-exit ;;
    *) startup=qemu-virt ;;
  esac
  for level in 0 1; do
    executable=$work_dir/retry-$target-O$level
    "$compiler" "-O$level" --target="$target" --startup="$startup" \
      --emit=exe "$work_dir/retry-startup.lisp" -o "$executable"
    "$compiler" "-O$level" --target="$target" --startup="$startup" \
      --emit=exe --dump-ir=all "$work_dir/retry-startup.lisp" \
      -o "$executable-dump" >"$work_dir/retry.ir"
    cmp "$executable" "$executable-dump"
    grep -q '^HIR main' "$work_dir/retry.ir"
    source_size=$(wc -c <"$work_dir/retry-startup.lisp")
    ir_size=$(wc -c <"$work_dir/retry.ir")
    test "$ir_size" -gt "$((64 * source_size + 4096))"
    case $target in
      x86_64-none-elf) "$executable-dump" ;;
      *) timeout 20 qemu-system-riscv64 -machine virt -nographic -monitor none \
           -bios none -kernel "$executable-dump" >"$work_dir/retry.out" 2>"$work_dir/retry.err" ;;
    esac
  done
done

cat >"$work_dir/custom.ld" <<'EOF_SCRIPT'
OUTPUT_FORMAT(elf64-x86-64)
ENTRY(_start)
SECTIONS { . = 0x500000; .text : { *(.text .text.*) } }
EOF_SCRIPT
custom=$work_dir/custom-script
"$compiler" --emit=exe --profile=freestanding --target=x86_64-none-elf \
  --startup=linux-exit --linker-script="$work_dir/custom.ld" \
  --map="$custom.map" \
  "$project_root/tests/bootstrap_cli_link_freestanding_exit.lisp" -o "$custom"
readelf -h "$custom" >"$work_dir/custom-header"
grep -q 'Entry point address: *0x500000' "$work_dir/custom-header"
test -s "$custom.map"

preserved=$work_dir/preserved
printf 'keep this output\n' >"$preserved"
cp "$preserved" "$work_dir/expected"
if "$compiler" --emit=exe --profile=freestanding --target=x86_64-none-elf \
  --startup=linux-exit --linker-script="$work_dir/missing.ld" \
  "$project_root/tests/bootstrap_cli_link_freestanding_exit.lisp" \
  -o "$preserved" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'link succeeded with a missing linker script' >&2
  exit 1
else
  test "$?" -eq 1
fi
cmp "$work_dir/expected" "$preserved"
if "$compiler" --emit=exe --profile=hosted --target=x86_64-none-elf \
  --startup=linux-exit "$project_root/tests/bootstrap_cli_link_freestanding_exit.lisp" \
  -o "$preserved" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'hosted profile linked for a none target' >&2
  exit 1
else
  test "$?" -eq 1
fi
cmp "$work_dir/expected" "$preserved"
if "$compiler" --emit=exe --profile=freestanding --target=x86_64-none-elf \
  --startup=linux-exit --map="$preserved" \
  "$project_root/tests/bootstrap_cli_link_freestanding_exit.lisp" \
  -o "$preserved" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'link accepted the output path as its map path' >&2
  exit 1
else
  test "$?" -eq 1
fi
cmp "$work_dir/expected" "$preserved"
if "$compiler" --emit=exe --profile=freestanding --target=x86_64-none-elf \
  --startup=linux-exit "$project_root/tests/bootstrap_cli_link_freestanding_exit.lisp" \
  -o "$work_dir/missing-output-dir/program" \
  >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'link unexpectedly succeeded for a missing output directory' >&2
  exit 1
else
  test "$?" -eq 1
fi
test ! -e "$work_dir/missing-output-dir/program"
test ! -s "$work_dir/stdout"
if "$compiler" --profile=freestanding --target=x86_64-none-elf \
  -c --startup=linux-exit "$project_root/tests/bootstrap_cli_link_freestanding_exit.lisp" \
  -o "$preserved" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo '-c accepted a startup option' >&2
  exit 1
else
  test "$?" -eq 1
fi
cmp "$work_dir/expected" "$preserved"
if "$compiler" --profile=freestanding --target=x86_64-none-elf \
  --startup=linux-exit "$work_dir/missing-source.lisp" -o "$preserved" \
  >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'missing source unexpectedly succeeded' >&2
  exit 1
else
  test "$?" -eq 1
fi
cmp "$work_dir/expected" "$preserved"

# The legacy two-path form emits an object and must reject link-only options.
for target in x86_64-none-elf riscv64-none-elf; do
  case $target in
    x86_64-none-elf) startup=linux-exit ;;
    *) startup=qemu-virt ;;
  esac
  "$compiler" --target="$target" -c \
    "$project_root/tests/bootstrap_cli_link_freestanding_exit.lisp" \
    -o "$work_dir/explicit-$target.o"
  "$compiler" --target="$target" \
    "$project_root/tests/bootstrap_cli_link_freestanding_exit.lisp" \
    "$work_dir/legacy-$target.o"
  cmp "$work_dir/explicit-$target.o" "$work_dir/legacy-$target.o"
  for option in "--startup=$startup" "--map=$work_dir/ignored.map" \
      "--entry=custom_entry" "--linker-script=$work_dir/custom.ld"; do
    if "$compiler" --target="$target" "$option" \
        "$project_root/tests/bootstrap_cli_link_freestanding_exit.lisp" \
        "$preserved" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
      echo "legacy object form accepted link-only option: $target $option" >&2
      exit 1
    else
      test "$?" -eq 1
    fi
    cmp "$work_dir/expected" "$preserved"
    test ! -s "$work_dir/stdout"
    grep -q 'unsupported target/profile/emit combination' "$work_dir/stderr"
    test ! -e "$work_dir/ignored.map"
  done
done

help=$work_dir/help
"$compiler" --help >"$help"
grep -q 'Freestanding executables: x86_64-none-elf (linux-exit) and riscv64-none-elf (qemu-virt)' "$help"
printf 'Native and Stage 0 none-ELF freestanding links passed O0/O1; QEMU startup, scripts, maps, rejection and output-preservation checks passed\n'
