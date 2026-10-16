#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$project_root/tests/bootstrap_test_runner.sh"
compiler=${1:-$project_root/build/pslcc-native}
target=${2:-x86_64-linux-gnu}
bootstrap_test_runner_init "$target"
command -v "$target_cc" >/dev/null 2>&1 || {
  echo "missing output-target compiler: $target_cc" >&2
  exit 2
}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

answer_source=$project_root/tests/bootstrap_cli_link_answer.lisp
main_source=$project_root/tests/harness_bootstrap_cli_link_answer.c
managed_source=$project_root/tests/bootstrap_cli_link_managed.lisp
managed_main=$project_root/tests/harness_bootstrap_cli_link_managed.c
runtime_main=$project_root/tests/harness_bootstrap_cli_link_runtime.c
archive_main=$project_root/tests/harness_bootstrap_cli_link_runtime_archive_main.c
archive_member=$project_root/tests/harness_bootstrap_cli_link_runtime_archive_member.c
source_runtime_main=$project_root/tests/harness_bootstrap_cli_link_runtime_source_main.c
source_runtime_source=$project_root/tests/bootstrap_cli_link_source_runtime.lisp

# The Windows-host adapter currently owns object output only. Verify that
# explicit link requests fail without replacing an existing destination.
if [ "$compiler_host_target" = x86_64-windows-gnu ]; then
  run_compiler_host "$compiler" -c "$answer_source" --target="$target" \
    -o "$work_dir/object.o"
  test -s "$work_dir/object.o"
  printf 'preserve prior output\n' > "$work_dir/preserved"
  cp "$work_dir/preserved" "$work_dir/expected"
  for kind in exe static shared; do
    if run_compiler_host "$compiler" "$answer_source" --target="$target" \
        --emit="$kind" -o "$work_dir/preserved"; then
      echo "Windows-host linker accepted unsupported artifact: $kind" >&2
      exit 1
    else
      test "$?" -eq 1
    fi
    cmp "$work_dir/expected" "$work_dir/preserved"
  done
  printf 'Windows-host object output and link-mode rejection passed\n'
  exit 0
fi

case $target in
  x86_64-linux-gnu) target_ar=${AR:-ar} ;;
  aarch64-linux-gnu) target_ar=${AARCH64_AR:-aarch64-linux-gnu-ar} ;;
  riscv64-linux-gnu) target_ar=${RISCV64_AR:-riscv64-linux-gnu-ar} ;;
  x86_64-windows-gnu) target_ar=${WINDOWS_AR:-x86_64-w64-mingw32-ar} ;;
esac

"$target_cc" -O2 -Wall -Wextra -Werror -c "$main_source" -o "$work_dir/main.o"
"$target_cc" -O2 -Wall -Wextra -Werror -c "$managed_main" -o "$work_dir/managed-main.o"
"$target_cc" -O2 -Wall -Wextra -Werror -c "$runtime_main" -o "$work_dir/runtime-main.o"
"$target_cc" -O2 -Wall -Wextra -Werror -c "$archive_main" -o "$work_dir/archive-main.o"
"$target_cc" -O2 -Wall -Wextra -Werror -c "$archive_member" -o "$work_dir/archive-member.o"
"$target_cc" -O2 -Wall -Wextra -Werror -c "$source_runtime_main" -o "$work_dir/source-runtime-main.o"
"$target_ar" rcs "$work_dir/libcli-runtime.a" "$work_dir/archive-member.o"

for level in 0 1; do
  run_compiler_host "$compiler" "-O$level" --target="$target" "$answer_source" -o "$work_dir/native-exe$target_suffix" \
    --emit=exe --link-input="$work_dir/main.o"
  run_target "$work_dir/native-exe$target_suffix"

  run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$answer_source" \
    -o "$work_dir/native-runtime-object$target_suffix" --emit=exe \
    --link-input="$work_dir/runtime-main.o"
  run_target "$work_dir/native-runtime-object$target_suffix"
  run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$answer_source" \
    -o "$work_dir/native-runtime-archive$target_suffix" --emit=exe \
    --link-input="$work_dir/archive-main.o" --link-input="$work_dir/libcli-runtime.a"
  run_target "$work_dir/native-runtime-archive$target_suffix"
  run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$source_runtime_source" \
    -o "$work_dir/native-runtime-source$target_suffix" --emit=exe \
    --link-input="$work_dir/source-runtime-main.o"
  run_target "$work_dir/native-runtime-source$target_suffix"

  run_compiler_host "$compiler" "-O$level" --target="$target" "$answer_source" -o "$work_dir/native.a" \
    --emit=static
  "$target_cc" -O2 "$main_source" "$work_dir/native.a" -o "$work_dir/native-static$target_suffix"
  run_target "$work_dir/native-static$target_suffix"

  long_output="$work_dir/$(printf '%0100d' 1)"
  run_compiler_host "$compiler" "-O$level" --target="$target" "$answer_source" \
    -o "$long_output" --emit=exe --link-input="$work_dir/main.o"
  run_target "$long_output"

  run_compiler_host "$compiler" "-O$level" --target="$target" "$answer_source" -o "$work_dir/native.so" \
    --emit=shared
  "$target_cc" -O2 "$main_source" "$work_dir/native.so" \
    -Wl,-rpath,"$work_dir" -o "$work_dir/native-shared$target_suffix"
  run_target "$work_dir/native-shared$target_suffix"

  "$project_root/pslcc" "-O$level" --target="$target" "$answer_source" -o "$work_dir/stage0-exe$target_suffix" \
    --emit=exe --link-input="$work_dir/main.o"
  run_target "$work_dir/stage0-exe$target_suffix"
  "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted "$answer_source" \
    -o "$work_dir/stage0-runtime-object$target_suffix" --emit=exe \
    --link-input="$work_dir/runtime-main.o"
  run_target "$work_dir/stage0-runtime-object$target_suffix"
  "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted "$answer_source" \
    -o "$work_dir/stage0-runtime-archive$target_suffix" --emit=exe \
    --link-input="$work_dir/archive-main.o" --link-input="$work_dir/libcli-runtime.a"
  run_target "$work_dir/stage0-runtime-archive$target_suffix"
  "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted "$source_runtime_source" \
    -o "$work_dir/stage0-runtime-source$target_suffix" --emit=exe \
    --link-input="$work_dir/source-runtime-main.o"
  run_target "$work_dir/stage0-runtime-source$target_suffix"
  "$project_root/pslcc" "-O$level" --target="$target" "$answer_source" -o "$work_dir/stage0.a" \
    --emit=static
  "$target_cc" -O2 "$main_source" "$work_dir/stage0.a" -o "$work_dir/stage0-static$target_suffix"
  run_target "$work_dir/stage0-static$target_suffix"
  stage0_long_output="$work_dir/$(printf '%0100d' 2)"
  "$project_root/pslcc" "-O$level" --target="$target" "$answer_source" \
    -o "$stage0_long_output" --emit=exe --link-input="$work_dir/main.o"
  run_target "$stage0_long_output"
  "$project_root/pslcc" "-O$level" --target="$target" "$answer_source" -o "$work_dir/stage0.so" \
    --emit=shared
  "$target_cc" -O2 "$main_source" "$work_dir/stage0.so" \
    -Wl,-rpath,"$work_dir" -o "$work_dir/stage0-shared$target_suffix"
  run_target "$work_dir/stage0-shared$target_suffix"

  run_compiler_host "$compiler" "-O$level" --target="$target" --profile=hosted "$managed_source" \
    -o "$work_dir/native-managed$target_suffix" --emit=exe \
    --link-input="$work_dir/managed-main.o"
  run_target "$work_dir/native-managed$target_suffix"
  "$project_root/pslcc" "-O$level" --target="$target" --profile=hosted "$managed_source" \
    -o "$work_dir/stage0-managed$target_suffix" --emit=exe \
    --link-input="$work_dir/managed-main.o"
  run_target "$work_dir/stage0-managed$target_suffix"
done

printf 'preserve existing output across link errors\n' > "$work_dir/preserved"
cp "$work_dir/preserved" "$work_dir/expected"
cat > "$work_dir/unknown-runtime.c" <<'EOF'
extern void psl_rt_unknown_link_entry(void);
int main(void) { psl_rt_unknown_link_entry(); return 0; }
EOF
"$target_cc" -c "$work_dir/unknown-runtime.c" -o "$work_dir/unknown-runtime.o"
if run_compiler_host "$compiler" --target="$target" "$answer_source" \
    --profile=hosted --emit=exe --link-input="$work_dir/unknown-runtime.o" \
    -o "$work_dir/preserved"; then
  echo 'native linker accepted an unknown runtime dependency' >&2
  exit 1
else
  test "$?" -eq 1
fi
cmp "$work_dir/expected" "$work_dir/preserved"

if run_compiler_host "$compiler" --target="$target" "$answer_source" -o "$work_dir/preserved" \
    --emit=exe --link-input="$work_dir/missing.o"; then
  echo 'native CLI accepted a missing link input' >&2
  exit 1
else
  test "$?" -eq 1
fi
cmp "$work_dir/expected" "$work_dir/preserved"

if [ "$target" = x86_64-linux-gnu ]; then
  printf 'not an object archive\n' > "$work_dir/not-object.a"
  if run_compiler_host "$compiler" --target="$target" "$answer_source" -o "$work_dir/preserved" \
      --emit=static --link-input="$work_dir/not-object.a"; then
    echo 'native static output accepted a non-object input' >&2
    exit 1
  else
    test "$?" -eq 1
  fi
  cmp "$work_dir/expected" "$work_dir/preserved"
else
  "$target_cc" -dumpmachine
fi

printf 'Native and Stage 0 executable, static, shared and runtime linking passed (%s)\n' "$target"
