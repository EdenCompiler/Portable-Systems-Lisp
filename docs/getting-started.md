# Getting started

[Documentation](README.md) / Getting started

Commands below run from the repository root on an x86-64 Linux compiler host.

- [Build and run](#build-and-run)
- [Objects and C interoperability](#objects-and-c-interoperability)
- [Managed values](#managed-values)
- [Libraries and IR](#libraries-and-ir)
- [Cross compilation](#cross-compilation)
- [Freestanding execution](#freestanding-execution)
- [Verification](#verification)

## Build and run

Install SBCL and a C compiler. The Stage 0 seed runs directly from the checkout:

```sh
./pslcc examples/native/arithmetic.lisp -o /tmp/psl-arithmetic
/tmp/psl-arithmetic
```

The example exits with status 0 after checking its arithmetic. SBCL runs the
compiler; a C toolchain links the executable. Object-only compilation uses
PSL's own instruction encoders and object writers.

To build the native compiler, install Make and run:

```sh
make native
build/pslcc-native examples/native/arithmetic.lisp -o /tmp/psl-native
/tmp/psl-native
```

`make native` builds eight PSL compiler units and links their explicit host
adapters and managed runtime. It does not certify the complete M8 release.
Both CLIs use `x86_64-linux-gnu`, `freestanding`, and `-O1` by default.
Use `-O0` for the baseline lowering. The [native guide](../bootstrap/README.md)
records native-specific limits and API details.

## Objects and C interoperability

Compile a relocatable object with `-c`:

```sh
./pslcc -c examples/basic/add.lisp -o /tmp/psl-add.o
cc examples/basic/harness_add.c /tmp/psl-add.o -o /tmp/psl-add
/tmp/psl-add
```

The source declares its C imports and exports explicitly. Ordinary Lisp calls
stay unqualified; imported calls use `ffi:call`. For a C file included by
`ffi:source`, compile the existing example and its receiver:

```sh
./pslcc -c examples/ffi/source_import.lisp -o /tmp/psl-source-import.o
cc examples/ffi/harness_source_import.c /tmp/psl-source-import.o \
  -o /tmp/psl-source-import
/tmp/psl-source-import
```

`ffi:source` paths are relative to the declaring Lisp file, including inside
`include` files. The compiler invokes the selected C compiler for declared C
sources and merges their objects. Typed Lisp object output without C sources
needs no external assembler or C compiler.

See [C imports and data](core.md#c-source-function-and-data-imports) for
signatures, raw pointers, C strings, and data symbols.

## Managed values

Choose the hosted profile explicitly:

```sh
./pslcc --profile=hosted examples/hosted/list.lisp -o /tmp/psl-list
/tmp/psl-list
```

Hosted source supports the documented tagged values, conses, UTF-8 strings,
symbols, runtime packages, closures, two values, and VALUE vectors. Linked
artifacts select the runtime modules the source needs. A `.o` alone retains
unresolved runtime imports that its eventual link must provide.

The default freestanding profile keeps runtime dependencies explicit. The
hosted subset is still growing; consult the [runtime contract](runtime.md) and
[implemented language](core.md#hosted-managed-values) before choosing a feature.

## Libraries and IR

The Linux compiler host can produce an executable, static archive, or shared
library. Additional C objects and libraries use repeated `--link-input=FILE`:

```sh
./pslcc --emit=static examples/basic/standalone.lisp -o /tmp/libpsl-example.a
./pslcc --emit=shared examples/basic/standalone.lisp -o /tmp/libpsl-example.so
./pslcc -c --dump-ir=all examples/native/arithmetic.lisp -o /tmp/psl-ir.o
```

`--dump-ir=hir|ssa|lir|all` writes verified IR to stdout. `-c` writes only a
relocatable object; an output name without `-c` requests a linked artifact.
Use modern option spellings with either compiler. The native compiler also
accepts legacy `SOURCE OUTPUT.o` syntax.

For reusable compilation stages, see the [compiler-library API](compiler.md).

## Cross compilation

Select a target independently from the profile. Macro expansion runs on the
compiler host; target execution is needed only for running and verifying the
result.

| Output target | Link toolchain | Runner used in tests |
| --- | --- | --- |
| `x86_64-windows-gnu` | MinGW-w64 | Wine |
| `aarch64-linux-gnu` | AArch64 GNU cross tools | `qemu-aarch64` with a target sysroot |
| `riscv64-linux-gnu` | RISC-V64 GNU cross tools | `qemu-riscv64` with a target sysroot |

For example, with MinGW-w64 and Wine installed:

```sh
./pslcc --target=x86_64-windows-gnu examples/native/arithmetic.lisp \
  -o /tmp/psl-arithmetic.exe
wine /tmp/psl-arithmetic.exe
```

Use `-c` to inspect a cross-target object without linking or running it. The
[current target matrix](roadmap.md#current-support-matrix) distinguishes
executable support from object output and lists ABI limits.

## Freestanding execution

The none targets use explicit startup and linker paths. This RISC-V example
needs the RISC-V bare-metal toolchain and QEMU system emulator:

```sh
./pslcc --target=riscv64-none-elf --startup=qemu-virt \
  examples/freestanding/virt_uart.lisp -o /tmp/psl-virt-uart.elf
qemu-system-riscv64 -machine virt -m 128M -nographic -bios none \
  -kernel /tmp/psl-virt-uart.elf -no-reboot
```

The image initializes its stack, writes to QEMU `virt`'s UART, and reports
`main`'s result through the test device. It links no firmware, OS, libc, or
hosted runtime. Other boards need their own startup and memory map.

The x86-64 `linux-exit` startup is an explicit Linux syscall shim used with
user-mode execution. It is a separate environment from an OS-free board.
See [target and profile rules](core.md#build-and-profiles) for supported
`--entry`, `--linker-script`, and `--map` behavior.

## Verification

Start with the local smoke suite:

```sh
sh tests/smoke.sh
make help
```

| Check | Command | Additional tools |
| --- | --- | --- |
| Stage 0 x86-64 Linux baseline | `sh tests/smoke.sh` | SBCL, C compiler, binutils |
| Stage 0 Windows target | `sh tests/windows.sh` | MinGW-w64 and Wine |
| Stage 0 AArch64 target | `sh tests/aarch64.sh` | AArch64 GNU tools, sysroot and QEMU |
| Stage 0 RISC-V and freestanding | `sh tests/riscv64.sh` | RISC-V Linux/bare-metal tools and QEMU |
| Native CLI | `make test-native-cli` | Built native compiler and C compiler |
| Every example against the seed | `make test-bootstrap-corpus` | Python 3 and the native compiler |

The native guide lists [component and cross-target checks](../bootstrap/README.md).
These focused suites support individual claims. The complete fresh three-stage
bootstrap and full corpus remain the [M8 release gate](roadmap.md#m8--self-hosting--in-progress).
