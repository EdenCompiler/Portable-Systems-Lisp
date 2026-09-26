#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
host_target=${1:-x86_64-linux-gnu}
host_suffix=

case $host_target in
  x86_64-linux-gnu) host_compiler=cc ;;
  x86_64-windows-gnu)
    host_compiler=x86_64-w64-mingw32-gcc
    host_suffix=.exe ;;
  aarch64-linux-gnu) host_compiler=aarch64-linux-gnu-gcc ;;
  riscv64-linux-gnu) host_compiler=riscv64-linux-gnu-gcc ;;
  *) echo "unsupported bootstrap host: $host_target" >&2; exit 2 ;;
esac

module_source() {
  case $1 in
    atoms|reader) printf '%s/bootstrap/frontend/%s.lisp' "$project_root" "$1" ;;
    *) printf '%s/bootstrap/%s.lisp' "$project_root" "$1" ;;
  esac
}

run_host() {
  case $host_target in
    x86_64-linux-gnu) "$@" ;;
    x86_64-windows-gnu) WINEDEBUG=-all wine "$@" ;;
    aarch64-linux-gnu)
      qemu-aarch64 -L "${AARCH64_SYSROOT:-/usr/aarch64-linux-gnu}" "$@" ;;
    riscv64-linux-gnu)
      qemu-riscv64 -L "${RISCV64_SYSROOT:-/usr/riscv64-linux-gnu}" "$@" ;;
  esac
}

if test -n "${PSL_NATIVE_CORE_OBJECT:-}"; then
  cp "$PSL_NATIVE_CORE_OBJECT" "$work_dir/native-core.o"
else
  "$project_root/pslcc" --target="$host_target" -c \
    "$project_root/bootstrap/native-core.lisp" \
    -o "$work_dir/native-core.o"
fi
"$host_compiler" -Wall -Wextra -Werror "$project_root/bootstrap/driver.c" \
  "$project_root/bootstrap/host/source.c" \
  "$work_dir/native-core.o" -o "$work_dir/pslcc-native-slice$host_suffix"
"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_hir.c" \
  "$work_dir/native-core.o" -o "$work_dir/hir-verifier$host_suffix"
run_host "$work_dir/hir-verifier$host_suffix"
"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_memory_hir.c" \
  "$work_dir/native-core.o" -o "$work_dir/memory-hir-verifier$host_suffix"
run_host "$work_dir/memory-hir-verifier$host_suffix"
"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_ir.c" \
  "$work_dir/native-core.o" -o "$work_dir/ir-verifier$host_suffix"
run_host "$work_dir/ir-verifier$host_suffix"
"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_layout.c" \
  "$work_dir/native-core.o" -o "$work_dir/layout-check$host_suffix"
run_host "$work_dir/layout-check$host_suffix"
"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_signatures.c" \
  "$work_dir/native-core.o" -o "$work_dir/signature-check$host_suffix"
run_host "$work_dir/signature-check$host_suffix" \
  "$project_root/bootstrap/binary.lisp" \
  "$project_root/bootstrap/arena.lisp" \
  "$project_root/bootstrap/frontend/atoms.lisp" \
  "$project_root/bootstrap/frontend/reader.lisp"

"$host_compiler" -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_source.c" \
  "$work_dir/native-core.o" -o "$work_dir/source-check$host_suffix"
run_host "$work_dir/source-check$host_suffix"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/include/native/main.lisp" "$work_dir/included.o"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/include/native/flat.lisp" "$work_dir/included-flat.o"
cmp "$work_dir/included.o" "$work_dir/included-flat.o"
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_answer.c" \
  "$work_dir/included.o" -o "$work_dir/included"
"$work_dir/included"

if test "$host_target" = x86_64-linux-gnu; then
  ln -s "$project_root/tests/include/native/shared.lisp" "$work_dir/shared-one.lisp"
  ln -s "$project_root/tests/include/native/shared.lisp" "$work_dir/shared-two.lisp"
  cat > "$work_dir/symlink-unit.lisp" <<'EOF'
(include "shared-one.lisp")
(include "shared-two.lisp")
(defun answer ()
  (declare (returns u64) (c-export :c))
  (included_helper 41))
EOF
  "$work_dir/pslcc-native-slice" "$work_dir/symlink-unit.lisp" "$work_dir/symlink-unit.o"
  cmp "$work_dir/included.o" "$work_dir/symlink-unit.o"
fi

for source in cycle-a missing invalid unterminated; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" \
      "$project_root/tests/include/native/$source.lisp" "$work_dir/invalid-include.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted invalid include: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid-include.o"
  case $source in
    cycle-a) grep -q 'circular source include' "$work_dir/stderr" ;;
    missing) grep -q 'cannot read source' "$work_dir/stderr" ;;
    invalid) grep -q 'invalid include form' "$work_dir/stderr" ;;
    unterminated) grep -q 'reader error' "$work_dir/stderr" ;;
  esac
done

for module in parser source; do
  run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/bootstrap/frontend/$module.lisp" "$work_dir/$module-native.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_$module.c" \
    "$work_dir/$module-native.o" -o "$work_dir/$module-native"
  "$work_dir/$module-native" "$project_root"/examples/*/*.lisp
  test "$(nm -u "$work_dir/$module-native.o" | wc -l)" -eq 0
done

for source in bootstrap_answer bootstrap_answer_hex \
    bootstrap_answer_arithmetic bootstrap_answer_overflow \
    bootstrap_conditionals bootstrap_recursion bootstrap_layouts \
    bootstrap_bitops bootstrap_lexical \
    bootstrap_declaration_order bootstrap_lisp_names; do
  run_host "$work_dir/pslcc-native-slice$host_suffix" "$project_root/tests/$source.lisp" \
    "$work_dir/$source.o"
  readelf -h "$work_dir/$source.o" | grep -q 'REL (Relocatable file)'
  cc -Wall -Wextra -Werror \
    "$project_root/tests/harness_bootstrap_answer.c" \
    "$work_dir/$source.o" -o "$work_dir/$source"
  "$work_dir/$source"
  run_host "$work_dir/pslcc-native-slice$host_suffix" "$project_root/tests/$source.lisp" \
    "$work_dir/$source-repeat.o"
  cmp "$work_dir/$source.o" "$work_dir/$source-repeat.o"
done

nm --defined-only "$work_dir/bootstrap_lisp_names.o" | \
  grep -q ' t helper-one$'
if nm -g --defined-only "$work_dir/bootstrap_lisp_names.o" | \
    grep -q ' helper-one$'; then
  echo 'native slice exported an internal hyphenated function' >&2
  exit 1
fi

cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_bitops.c" \
  "$work_dir/bootstrap_bitops.o" -o "$work_dir/bitops"
"$work_dir/bitops"

for source in bootstrap_lexical_duplicate bootstrap_lexical_scope; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" \
      "$project_root/tests/$source.lisp" "$work_dir/$source.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted invalid lexical source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/$source.o"
done

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_two_functions.lisp" \
  "$work_dir/two-functions.o"
nm -g --defined-only "$work_dir/two-functions.o" | grep -q ' answer$'
nm -g --defined-only "$work_dir/two-functions.o" | grep -q ' other_answer$'
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_two_functions.c" \
  "$work_dir/two-functions.o" -o "$work_dir/two-functions"
"$work_dir/two-functions"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_two_functions.lisp" \
  "$work_dir/two-functions-repeat.o"
cmp "$work_dir/two-functions.o" "$work_dir/two-functions-repeat.o"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_local_calls.lisp" \
  "$work_dir/local-calls.o"
test "$(nm -u "$work_dir/local-calls.o" | wc -l)" -eq 0
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_local_calls.c" \
  "$work_dir/local-calls.o" -o "$work_dir/local-calls"
"$work_dir/local-calls"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_parameters.lisp" \
  "$work_dir/parameters.o"
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_parameters.c" \
  "$work_dir/parameters.o" -o "$work_dir/parameters"
"$work_dir/parameters"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_six_arguments.lisp" \
  "$work_dir/six-arguments.o"
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_six_arguments.c" \
  "$work_dir/six-arguments.o" -o "$work_dir/six-arguments"
"$work_dir/six-arguments"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_six_arguments.lisp" \
  "$work_dir/six-arguments-repeat.o"
cmp "$work_dir/six-arguments.o" "$work_dir/six-arguments-repeat.o"

# Cross the six-register SysV boundary with odd/even stack counts, narrow
# signed values, pointers, nested/recursive calls, and ordered side effects.
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_stack_arguments.lisp" "$work_dir/stack-arguments.o"
test "$(nm -u "$work_dir/stack-arguments.o" | wc -l)" -eq 0
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_stack_arguments.c" \
  "$work_dir/stack-arguments.o" -o "$work_dir/stack-arguments"
"$work_dir/stack-arguments"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_stack_arguments.lisp" "$work_dir/stack-arguments-repeat.o"
cmp "$work_dir/stack-arguments.o" "$work_dir/stack-arguments-repeat.o"
"$project_root/pslcc" -c "$project_root/tests/bootstrap_stack_arguments.lisp" \
  -o "$work_dir/stack-arguments-stage0.o"
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_stack_arguments.c" \
  "$work_dir/stack-arguments-stage0.o" -o "$work_dir/stack-arguments-stage0"
"$work_dir/stack-arguments-stage0"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_usize.lisp" \
  "$work_dir/usize.o"
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_usize.c" \
  "$work_dir/usize.o" -o "$work_dir/usize"
"$work_dir/usize"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_usize.lisp" \
  "$work_dir/usize-repeat.o"
cmp "$work_dir/usize.o" "$work_dir/usize-repeat.o"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_integer_types.lisp" \
  "$work_dir/integer-types.o"
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_integer_types.c" \
  "$work_dir/integer-types.o" -o "$work_dir/integer-types"
"$work_dir/integer-types"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_integer_types.lisp" \
  "$work_dir/integer-types-repeat.o"
cmp "$work_dir/integer-types.o" "$work_dir/integer-types-repeat.o"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_mixed_integers.lisp" \
  "$work_dir/mixed-integers.o"
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_mixed_integers.c" \
  "$work_dir/mixed-integers.o" -o "$work_dir/mixed-integers"
"$work_dir/mixed-integers"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_mixed_integers.lisp" \
  "$work_dir/mixed-integers-repeat.o"
cmp "$work_dir/mixed-integers.o" "$work_dir/mixed-integers-repeat.o"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/bootstrap/ir/integer_types.lisp" \
  "$work_dir/integer-module.o"
test "$(nm -u "$work_dir/integer-module.o" | wc -l)" -eq 0
readelf -h "$work_dir/integer-module.o" | grep -q 'REL (Relocatable file)'
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_integer_module.c" \
  "$work_dir/integer-module.o" -o "$work_dir/integer-module"
"$work_dir/integer-module"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/bootstrap/ir/integer_types.lisp" \
  "$work_dir/integer-module-repeat.o"
cmp "$work_dir/integer-module.o" "$work_dir/integer-module-repeat.o"
"$project_root/pslcc" --target=x86_64-linux-gnu -c \
  "$project_root/bootstrap/ir/integer_types.lisp" \
  -o "$work_dir/integer-module-stage0.o"
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_integer_module.c" \
  "$work_dir/integer-module-stage0.o" -o "$work_dir/integer-module-stage0"
"$work_dir/integer-module-stage0"

for source in bootstrap_usize bootstrap_integer_types bootstrap_mixed_integers; do
  "$project_root/pslcc" --target=x86_64-linux-gnu -c \
    "$project_root/tests/$source.lisp" -o "$work_dir/$source-stage0.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_$source.c" \
    "$work_dir/$source-stage0.o" -o "$work_dir/$source-stage0"
  "$work_dir/$source-stage0"
done

# The native executable compiles real pointer-using compiler modules.
for module in binary arena reader atoms; do
  run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$(module_source "$module")" "$work_dir/$module-module.o"
  test "$(nm -u "$work_dir/$module-module.o" | wc -l)" -eq 0
  readelf -h "$work_dir/$module-module.o" | grep -q 'REL (Relocatable file)'
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_$module.c" \
    "$work_dir/$module-module.o" -o "$work_dir/$module-module"
  "$work_dir/$module-module" "$project_root"/examples/*/*.lisp \
    >"$work_dir/$module-native-output"
  "$project_root/pslcc" -c "$(module_source "$module")" \
    -o "$work_dir/$module-module-stage0.o"
  cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_$module.c" \
    "$work_dir/$module-module-stage0.o" -o "$work_dir/$module-module-stage0"
  "$work_dir/$module-module-stage0" "$project_root"/examples/*/*.lisp \
    >"$work_dir/$module-stage0-output"
  cmp "$work_dir/$module-native-output" "$work_dir/$module-stage0-output"
  run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$(module_source "$module")" "$work_dir/$module-module-repeat.o"
  cmp "$work_dir/$module-module.o" "$work_dir/$module-module-repeat.o"
done

if test "$host_target" = x86_64-linux-gnu; then
  PATH=/nonexistent "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/bootstrap/binary.lisp" "$work_dir/binary-no-tools.o"
  cmp "$work_dir/binary-module.o" "$work_dir/binary-no-tools.o"
  PATH=/nonexistent "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_stack_arguments.lisp" "$work_dir/stack-no-tools.o"
  cmp "$work_dir/stack-arguments.o" "$work_dir/stack-no-tools.o"
fi

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_pointers.lisp" "$work_dir/pointers.o"
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_pointers.c" \
  "$work_dir/pointers.o" -o "$work_dir/pointers"
"$work_dir/pointers"
"$project_root/pslcc" -c "$project_root/tests/bootstrap_pointers.lisp" \
  -o "$work_dir/pointers-stage0.o"
cc -Wall -Wextra -Werror "$project_root/tests/harness_bootstrap_pointers.c" \
  "$work_dir/pointers-stage0.o" -o "$work_dir/pointers-stage0"
"$work_dir/pointers-stage0"
run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_pointers.lisp" "$work_dir/pointers-repeat.o"
cmp "$work_dir/pointers.o" "$work_dir/pointers-repeat.o"

for source in "$project_root"/tests/bootstrap_pointer_errors/*.lisp; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" \
      "$source" "$work_dir/invalid-pointer.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted invalid pointer source: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/invalid-pointer.o"
done

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_parameter_calls.lisp" \
  "$work_dir/parameter-calls.o"
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_answer.c" \
  "$work_dir/parameter-calls.o" -o "$work_dir/parameter-calls"
"$work_dir/parameter-calls"
# LIR materializes argument expressions in frame slots before loading registers.
# The C caller checks nested calls; temporary evaluation pushes are no longer
# needed across call sites.

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_local_functions.lisp" \
  "$work_dir/local-functions.o"
nm -g --defined-only "$work_dir/local-functions.o" | grep -q ' answer$'
if nm -g --defined-only "$work_dir/local-functions.o" | \
    grep -q ' local_'; then
  echo 'native slice exported an internal Lisp function' >&2
  exit 1
fi
nm --defined-only "$work_dir/local-functions.o" | grep -q ' t local_before$'
nm --defined-only "$work_dir/local-functions.o" | grep -q ' t local_after$'
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_answer.c" \
  "$work_dir/local-functions.o" -o "$work_dir/local-functions"
"$work_dir/local-functions"

run_host "$work_dir/pslcc-native-slice$host_suffix" \
  "$project_root/tests/bootstrap_forward_call.lisp" \
  "$work_dir/forward-call.o"
test "$(nm -u "$work_dir/forward-call.o" | wc -l)" -eq 0
cc -Wall -Wextra -Werror \
  "$project_root/tests/harness_bootstrap_answer.c" \
  "$work_dir/forward-call.o" -o "$work_dir/forward-call"
"$work_dir/forward-call"

if run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/examples/basic/add.lisp" "$work_dir/unsupported.o" \
    >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'native slice accepted unsupported source' >&2
  exit 1
fi
grep -q 'unsupported or malformed source' "$work_dir/stderr"
test ! -e "$work_dir/unsupported.o"

if run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_duplicate_exports.lisp" \
    "$work_dir/duplicate.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'native slice accepted duplicate export names' >&2
  exit 1
fi
test ! -e "$work_dir/duplicate.o"

if run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_uppercase_export.lisp" \
    "$work_dir/uppercase.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'native slice accepted an unnormalized export name' >&2
  exit 1
fi
test ! -e "$work_dir/uppercase.o"

if run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_export_hyphen.lisp" \
    "$work_dir/export-hyphen.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'native slice accepted a hyphenated C export' >&2
  exit 1
fi
test ! -e "$work_dir/export-hyphen.o"

if run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_empty_call.lisp" \
    "$work_dir/empty-call.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'native slice accepted an empty call form' >&2
  exit 1
fi
test ! -e "$work_dir/empty-call.o"

if run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_wrong_arity.lisp" \
    "$work_dir/wrong-arity.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'native slice accepted a call with the wrong arity' >&2
  exit 1
fi
test ! -e "$work_dir/wrong-arity.o"

if run_host "$work_dir/pslcc-native-slice$host_suffix" \
    "$project_root/tests/bootstrap_usize_cross_type.lisp" \
    "$work_dir/usize-cross-type.o" >"$work_dir/stdout" 2>"$work_dir/stderr"; then
  echo 'native slice accepted a mixed u64/usize call' >&2
  exit 1
fi
test ! -e "$work_dir/usize-cross-type.o"

for source in bootstrap_integer_range bootstrap_unsigned_negative; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" \
      "$project_root/tests/$source.lisp" "$work_dir/$source.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted an out-of-range integer: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/$source.o"
done

for source in bootstrap_mixed_operator bootstrap_mixed_argument bootstrap_cast_arity; do
  if run_host "$work_dir/pslcc-native-slice$host_suffix" \
      "$project_root/tests/$source.lisp" "$work_dir/$source.o" \
      >"$work_dir/stdout" 2>"$work_dir/stderr"; then
    echo "native slice accepted an invalid integer type relationship: $source" >&2
    exit 1
  fi
  test ! -e "$work_dir/$source.o"
done

if test "$host_target" != x86_64-linux-gnu; then
  "$project_root/pslcc" --target=x86_64-linux-gnu -c \
    "$project_root/bootstrap/native-core.lisp" \
    -o "$work_dir/native-reference-core.o"
  cc -Wall -Wextra -Werror "$project_root/bootstrap/driver.c" \
  "$project_root/bootstrap/host/source.c" \
    "$work_dir/native-reference-core.o" -o "$work_dir/native-reference"
  "$work_dir/native-reference" "$project_root/tests/bootstrap_answer.lisp" \
    "$work_dir/native-reference.o"
  cmp "$work_dir/bootstrap_answer.o" "$work_dir/native-reference.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_two_functions.lisp" \
    "$work_dir/native-reference-two.o"
  cmp "$work_dir/two-functions.o" "$work_dir/native-reference-two.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_local_calls.lisp" \
    "$work_dir/native-reference-calls.o"
  cmp "$work_dir/local-calls.o" "$work_dir/native-reference-calls.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_parameter_calls.lisp" \
    "$work_dir/native-reference-parameter-calls.o"
  cmp "$work_dir/parameter-calls.o" \
    "$work_dir/native-reference-parameter-calls.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_six_arguments.lisp" \
    "$work_dir/native-reference-six-arguments.o"
  cmp "$work_dir/six-arguments.o" \
    "$work_dir/native-reference-six-arguments.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_usize.lisp" \
    "$work_dir/native-reference-usize.o"
  cmp "$work_dir/usize.o" "$work_dir/native-reference-usize.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_integer_types.lisp" \
    "$work_dir/native-reference-integer-types.o"
  cmp "$work_dir/integer-types.o" "$work_dir/native-reference-integer-types.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_mixed_integers.lisp" \
    "$work_dir/native-reference-mixed-integers.o"
  cmp "$work_dir/mixed-integers.o" "$work_dir/native-reference-mixed-integers.o"
  "$work_dir/native-reference" \
    "$project_root/bootstrap/ir/integer_types.lisp" \
    "$work_dir/native-reference-integer-module.o"
  cmp "$work_dir/integer-module.o" "$work_dir/native-reference-integer-module.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_local_functions.lisp" \
    "$work_dir/native-reference-local-functions.o"
  cmp "$work_dir/local-functions.o" \
    "$work_dir/native-reference-local-functions.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_forward_call.lisp" \
    "$work_dir/native-reference-forward-call.o"
  cmp "$work_dir/forward-call.o" \
    "$work_dir/native-reference-forward-call.o"
  "$work_dir/native-reference" \
    "$project_root/tests/bootstrap_recursion.lisp" \
    "$work_dir/native-reference-recursion.o"
  cmp "$work_dir/bootstrap_recursion.o" \
    "$work_dir/native-reference-recursion.o"
  for source in bootstrap_bitops bootstrap_lexical \
      bootstrap_declaration_order bootstrap_lisp_names; do
    "$work_dir/native-reference" "$project_root/tests/$source.lisp" \
      "$work_dir/native-reference-$source.o"
    cmp "$work_dir/$source.o" "$work_dir/native-reference-$source.o"
  done
  "$work_dir/native-reference" "$project_root/tests/bootstrap_stack_arguments.lisp" \
    "$work_dir/stack-arguments-reference.o"
  cmp "$work_dir/stack-arguments.o" "$work_dir/stack-arguments-reference.o"
  for module in binary arena reader atoms; do
    "$work_dir/native-reference" "$(module_source "$module")" \
      "$work_dir/$module-module-reference.o"
    cmp "$work_dir/$module-module.o" "$work_dir/$module-module-reference.o"
  done
  "$work_dir/native-reference" "$project_root/tests/bootstrap_pointers.lisp" \
    "$work_dir/pointers-reference.o"
  cmp "$work_dir/pointers.o" "$work_dir/pointers-reference.o"
fi

"$project_root/pslcc" -O0 --target="$host_target" -c \
  "$project_root/bootstrap/native-core.lisp" \
  -o "$work_dir/native-core-O0.o"
"$host_compiler" -Wall -Wextra -Werror "$project_root/bootstrap/driver.c" \
  "$project_root/bootstrap/host/source.c" \
  "$work_dir/native-core-O0.o" -o "$work_dir/pslcc-native-O0$host_suffix"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_forward_call.lisp" \
  "$work_dir/forward-call-O0.o"
cmp "$work_dir/forward-call.o" "$work_dir/forward-call-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_recursion.lisp" \
  "$work_dir/recursion-O0.o"
cmp "$work_dir/bootstrap_recursion.o" "$work_dir/recursion-O0.o"
for source in bootstrap_bitops bootstrap_lexical \
    bootstrap_declaration_order bootstrap_lisp_names; do
  run_host "$work_dir/pslcc-native-O0$host_suffix" \
    "$project_root/tests/$source.lisp" "$work_dir/$source-O0.o"
  cmp "$work_dir/$source.o" "$work_dir/$source-O0.o"
done
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_six_arguments.lisp" \
  "$work_dir/six-arguments-O0.o"
cmp "$work_dir/six-arguments.o" "$work_dir/six-arguments-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_usize.lisp" \
  "$work_dir/usize-O0.o"
cmp "$work_dir/usize.o" "$work_dir/usize-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_integer_types.lisp" \
  "$work_dir/integer-types-O0.o"
cmp "$work_dir/integer-types.o" "$work_dir/integer-types-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_mixed_integers.lisp" \
  "$work_dir/mixed-integers-O0.o"
cmp "$work_dir/mixed-integers.o" "$work_dir/mixed-integers-O0.o"
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/bootstrap/ir/integer_types.lisp" \
  "$work_dir/integer-module-O0.o"
cmp "$work_dir/integer-module.o" "$work_dir/integer-module-O0.o"

for module in binary arena reader atoms; do
  run_host "$work_dir/pslcc-native-O0$host_suffix" \
    "$(module_source "$module")" "$work_dir/$module-module-O0.o"
  cmp "$work_dir/$module-module.o" "$work_dir/$module-module-O0.o"
done
run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_pointers.lisp" "$work_dir/pointers-O0.o"
cmp "$work_dir/pointers.o" "$work_dir/pointers-O0.o"

run_host "$work_dir/pslcc-native-O0$host_suffix" \
  "$project_root/tests/bootstrap_stack_arguments.lisp" "$work_dir/stack-arguments-O0.o"
cmp "$work_dir/stack-arguments.o" "$work_dir/stack-arguments-O0.o"

if test -n "${PSL_NATIVE_OBJECT_SNAPSHOT_DIR:-}"; then
  mkdir -p "$PSL_NATIVE_OBJECT_SNAPSHOT_DIR"
  for object in "$work_dir"/*.o; do
    case ${object##*/} in native-core.o) continue ;; esac
    cp "$object" "$PSL_NATIVE_OBJECT_SNAPSHOT_DIR/${object##*/}"
  done
fi

echo "PSL native source-to-object compiler slice passed on $host_target"
