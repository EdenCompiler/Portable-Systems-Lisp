# Portable Systems Lisp

A native Lisp compiler for typed machine code, C interoperability, and
freestanding programs. PSL encodes its own instructions and writes ELF/COFF
objects for x86-64, AArch64, and RISC-V64.

The project is experimental. **M8 self hosting is in progress.** The hosted
profile implements a managed-value subset; ANSI Common Lisp completion is M9.

[Get started](docs/getting-started.md) · [Examples](examples/README.md) ·
[Language reference](docs/core.md) · [Documentation](docs/README.md) ·
[Roadmap](docs/roadmap.md)

## Run your first program

On x86-64 Linux, install SBCL and a C compiler, then run from the repository
root:

```sh
./pslcc examples/native/arithmetic.lisp -o /tmp/psl-arithmetic
/tmp/psl-arithmetic
```

The program checks its result and exits with status 0. `./pslcc` runs the
Stage 0 compiler under SBCL; it needs no separate compiler build. The system
C toolchain performs final linking.

To build and use the native compiler, also install Make:

```sh
make native
build/pslcc-native examples/native/arithmetic.lisp -o /tmp/psl-native
/tmp/psl-native
```

See [Getting started](docs/getting-started.md) for objects, C calls, managed
values, libraries, and cross compilation.

## What PSL code looks like

```lisp
(defun add42 (value)
  (declare (type u64 value)
           (returns u64)
           (c-export :c))
  (wrap+ value 42))
```

This [complete source file](examples/basic/standalone.lisp) exports a function
for C callers. Types and layout are explicit. `wrap+` requests machine-width
wraparound; standard Common Lisp names retain their meanings. C declarations
and calls use the `ffi:` package, and macros execute on the compiler host.

## Targets and profiles

| Target | ABI / object format | Execution evidence |
| --- | --- | --- |
| `x86_64-linux-gnu` | System V / ELF64 | Linux programs and C interoperability |
| `x86_64-windows-gnu` | Microsoft x64 / COFF | MinGW-w64 links; Wine runs interoperability tests |
| `aarch64-linux-gnu` | AAPCS64 / ELF64 | GNU cross linking and QEMU user-mode execution |
| `riscv64-linux-gnu` | LP64D / ELF64 | GNU cross linking and QEMU user-mode execution |
| `x86_64-none-elf` | System V / ELF64 | Static image with explicit `linux-exit` syscall startup |
| `riscv64-none-elf` | LP64D / ELF64 | QEMU `virt` image with explicit startup and memory map |

Both profiles accept the typed machine subset. The default `freestanding`
profile adds no implicit libc, collector, or hosted startup. Explicit
`--profile=hosted` enables the documented managed values and runtime modules on
the four OS targets. Architecture, ABI, object format, and profile are separate
choices; the [implemented contract](docs/core.md) gives their exact limits.

A Linux compiler host supports object output, executables, static archives,
and shared libraries through the selected toolchain. A native Windows compiler
host currently supports object output. Other bare-metal boards need their own
startup and memory map.

## Development

```sh
sh tests/smoke.sh
make help
```

Smoke tests cover the compiler pipeline, deterministic objects, C ABI behavior,
and rejection cases. Target execution needs the corresponding cross toolchain
and runner; see [verification commands](docs/getting-started.md#verification).
PSL writes Lisp machine code directly. External C compilers, linkers, and
inspection tools serve interop and verification boundaries.

The native compiler builds eight PSL units, including source loading, verified
HIR/SSA/LIR, optimization, encoders, object writers, and its driver. Component
fixed-point tests have passed; the complete fresh Stage 1–3 corpus is still the
[M8 release gate](docs/roadmap.md#m8--self-hosting--in-progress).

For implementation work, read the [source architecture](docs/architecture.md)
and [contributor instructions](AGENTS.md).
