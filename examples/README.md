# Examples

Examples are grouped by the compiler feature they demonstrate. Start with
`native/` for typed programs written entirely in Lisp, then `hosted/` for
managed values. The interop examples have
matching `harness_*.c` files. The `ffi:source` examples keep their C source
in the same directory because PSL resolves that path relative to the Lisp
file.

## Native Lisp programs

- [arithmetic.lisp](native/arithmetic.lisp): functions, calls, and wrapping
  machine arithmetic.
- [recursion.lisp](native/recursion.lisp): recursive factorial.
- [macros.lisp](native/macros.lisp): a Lisp macro expanded during compilation.
- [layout.lisp](native/layout.lisp): packed structure size and field offsets.
- [no_allocation.lisp](native/no_allocation.lisp): a certified call to a
  nonallocating Lisp function.

Each file defines `main` and returns exit status 0 when its own check passes.
They use no `ffi:` forms, C source files, or C harnesses. Stage 0 still requires
`(c-export :c)` on each function, including `main`, and uses the system C
toolchain to link Linux or Windows executables.

From the repository root, compile and run one:

```sh
./pslcc examples/native/arithmetic.lisp -o /tmp/psl-arithmetic
/tmp/psl-arithmetic
echo $?
```

Use `-c` to produce an object without invoking a C compiler:

```sh
./pslcc -c examples/native/arithmetic.lisp -o /tmp/psl-arithmetic.o
```

For Windows, compile with `--target=x86_64-windows-gnu` and a `.exe` output;
MinGW-w64 links it and Wine can run it on Linux:

```sh
./pslcc --target=x86_64-windows-gnu examples/native/arithmetic.lisp \
  -o /tmp/psl-arithmetic.exe
wine /tmp/psl-arithmetic.exe
```

## Hosted values

- [list.lisp](hosted/list.lisp): tagged fixnums, conses, dynamic truth, and GC.
- [immediate.lisp](hosted/immediate.lisp): tagged values and identity without
  a collector dependency.
- [gc_list.lisp](hosted/gc_list.lisp): a live list across automatic and explicit
  collections.
- [string_package.lisp](hosted/string_package.lisp): byte strings, symbols,
  packages, and interning.
- [closure.lisp](hosted/closure.lisp): a lexical closure that retains a captured
  value through collection.
- [closure_module.lisp](hosted/closure_module.lisp): a second closure-bearing
  object that can link beside `closure.lisp`.
- [multiple_values.lisp](hosted/multiple_values.lisp): two returned values.

These are Lisp source files without C companions. They require the hosted
profile and select only the runtime modules they use:

```sh
./pslcc --profile=hosted examples/hosted/list.lisp -o /tmp/psl-list
/tmp/psl-list
echo $?
```

## Freestanding

- [virt_uart.lisp](freestanding/virt_uart.lisp): pure Lisp code writes one
  byte to QEMU `virt`'s UART using a volatile raw pointer. The selected
  RISC-V startup initializes the stack and reports `main`'s status to QEMU.

```sh
./pslcc --target=riscv64-none-elf --startup=qemu-virt \
  examples/freestanding/virt_uart.lisp -o /tmp/virt-uart.elf
qemu-system-riscv64 -machine virt -m 128M -nographic -bios none \
  -kernel /tmp/virt-uart.elf -no-reboot
```

## Basic

- [add.lisp](basic/add.lisp): typed functions, a C export, a C import, and a macro.
- [program.lisp](basic/program.lisp): executable entry point.
- [standalone.lisp](basic/standalone.lisp): static and shared library export.

## C ABI

- [aggregate.lisp](abi/aggregate.lisp): C structs passed by value.
- [float.lisp](abi/float.lisp): floating point arguments.
- [stack.lisp](abi/stack.lisp): stack arguments.
- [void.lisp](abi/void.lisp): void calls.
- [layout.lisp](abi/layout.lisp): C struct layout.
- [windows_odd_aggregate.lisp](abi/windows_odd_aggregate.lisp): a 12-byte
  C struct passed by reference under Microsoft x64.
- [aarch64_hfa.lisp](abi/aarch64_hfa.lisp): four-float homogeneous aggregates,
  nested fields, and floating-register exhaustion under AAPCS64.
- [riscv64_edges.lisp](abi/riscv64_edges.lisp): integer/stack register splits,
  ninth arguments, and floating-register fallback under LP64D.

## FFI

- [source_import.lisp](ffi/source_import.lisp): include and call [math.c](ffi/math.c).
- [data_import.lisp](ffi/data_import.lisp): imported and exported data.
- [shared_data.lisp](ffi/shared_data.lisp): shared library data with
  [data_provider.c](ffi/data_provider.c).
- [data_only.lisp](ffi/data_only.lisp): object containing only data.

## Memory and optimization

- [memory.lisp](memory/memory.lisp): packed structs and pointer operations.
- [optimizer.lisp](optimization/optimizer.lisp): behavior checked under `-O0`
  and `-O1`.

To try the C interop example instead:

```sh
./pslcc -c examples/basic/add.lisp -o /tmp/psl-add.o
cc examples/basic/harness_add.c /tmp/psl-add.o -o /tmp/psl-add
/tmp/psl-add
```

Run `sh tests/smoke.sh` for x86-64 Linux, `sh tests/windows.sh` for Windows,
`sh tests/aarch64.sh` for AArch64, or `sh tests/riscv64.sh` for RISC-V64
Linux and freestanding QEMU execution.
