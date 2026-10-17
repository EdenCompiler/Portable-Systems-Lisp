# Native bootstrap components

[Documentation](../docs/README.md) / Native compiler

This guide explains how to build and use the native compiler, then points to the
component references and verification gates. It describes the implemented
bootstrap slice, not a completed Stage 1–3 release. The full fresh-generation
and corpus proof remains open; see [the roadmap](../docs/roadmap.md).

## Build and try it

From the repository root on a supported x86-64 Linux host:

```sh
make
build/pslcc-native -c examples/basic/standalone.lisp -o build/standalone.o
./pslcc --profile=hosted -c bootstrap/native-core.lisp -o /tmp/psl-native-core.o
```

The first command uses the SBCL seed to build the native compiler. The next commands
emit objects with the native compiler and Stage 0, respectively. For an executable on a hosted OS
target, use `SOURCE -o OUTPUT`; the compiler invokes the selected C
compiler/linker at the explicit hosted link boundary. `-c SOURCE -o OUTPUT`
and the legacy `SOURCE OUTPUT` form emit an object.

Common options are `--target=TRIPLE`, `--profile=hosted|freestanding`,
`-O0` and `-O1`. They may be placed around the source and output arguments;
separate-value forms `--target TRIPLE` and `--profile PROFILE` are accepted.
The last repeated option wins. `--emit=exe|static|shared` selects a linked
artifact, and repeated `--link-input PATH` adds C objects or libraries. Runtime
imports select their declared runtime modules and dependencies. See
[CLI guide](../docs/getting-started.md), [native contract](../docs/core.md#native-bootstrap-subset),
and [compiler-library API](../docs/compiler.md) for details.

## Verify changes

Run the broad smoke check after compiler changes, then the focused gate for the
component being changed:

```sh
sh tests/smoke.sh
sh tests/bootstrap_native_compiler.sh
sh tests/bootstrap_self_core.sh
```

Other useful gates include `tests/bootstrap_modules.sh`,
`tests/bootstrap_binary.sh`, `tests/bootstrap_reader.sh`,
`tests/bootstrap_parser.sh`, `tests/bootstrap_component.sh arena`,
`tests/bootstrap_component.sh atoms`, and `tests/bootstrap_elf64.sh`. Targeted
C harnesses, object inspection and target runners are used where applicable.
The native compiler regression builds API receivers at both optimization
levels; compiler-generation gates rebuild their compiler units and are not
replaced by cached test fixtures.

## What the native compiler contains

`native-core.lisp` includes the target-independent compiler pipeline and
instruction/object backends as one translation unit. Eight separately compiled
hosted PSL units provide the core, driver/storage, source-unit loader, file
input, host paths, compiler controller, output and diagnostics. Their ownership
and dependency boundaries are mapped in [the compiler architecture](../docs/architecture.md).

The C boundary is explicit. `bootstrap/native_api.h` shares record layouts and
function declarations with C callers. PSL uses `ffi:source` for C source,
`ffi:import-function` for signatures and `ffi:call` for calls. The C driver is
a process trampoline; allocation, parser/compiler work, storage lifecycle and
diagnostic selection belong to PSL units. The primitive host adapters provide
OS, stream, process and toolchain operations.

The compiler host's runtime dependencies are separate from the target program's
profile. Compiler units that use managed services are built hosted and linked
with their declared runtime modules. A user compilation can still select
freestanding output, which adds no implicit libc, GC, hosted startup or OS
support. Object-only user compilations leave runtime imports for the caller
to resolve; linked hosted artifacts select the required modules.

## Implemented slice and limits

The native compiler emits x86-64 Linux ELF, x86-64 Windows COFF, AArch64 Linux
ELF and RISC-V64 Linux ELF objects. Its source compiler and target object
writers are implemented in PSL; external C tools are used only for explicit
C-source compilation, final linking, archiving or execution. Linux compiler
hosts can link supported installed target toolchains. A native Windows compiler
host currently supports object output and rejects executable, archive and shared
link requests.

The implemented language subset includes typed machine integers, pointers,
void operations, scalar floating literals/calls, C calls/data, C layouts and supported
natural/floating aggregates, Boolean control flow and lexical bindings. Hosted
profile adds tagged managed values, precise roots, strings, symbols, packages,
closures and mutable VALUE vectors. The native macro evaluator and source
language remain bounded subsets. These statements describe the native slice;
they do not narrow Stage 0's separate contract. Consult
[the implemented contract](../docs/core.md) for exact semantics and limits.

Compiler-owned syntax and IR records remain typed caller-owned arenas. The
macro-definition registry uses managed vectors through opaque runtime handles.
Broader source/interop parity and the complete M8 release gate remain work
in progress. Object emission alone does
not establish that a target can execute on the current host.

## Reference sections

The sections below retain the established target and API reference anchors for
existing links. Use the table of contents to jump to the relevant boundary.

- [AArch64 output](#native-aarch64-output)
- [RISC-V64 output](#native-risc-v64-output)
- [Windows output](#native-windows-output)
- [Hosted object output](#hosted-object-output)
- [Hosted source input](#hosted-source-input)
- [Hosted canonical paths](#hosted-canonical-paths)

## Native AArch64 output

Select `--target=aarch64-linux-gnu`; it may appear before or after the
optimization option. The target uses AAPCS64 and ELF. The backend handles the
implemented integer, pointer, Boolean, void, direct-call, control-flow and
memory subset, with the C ABI's register and stack argument rules.

```sh
make
build/pslcc-native --target=aarch64-linux-gnu \
  tests/bootstrap_stack_arguments.lisp build/stack-aarch64.o
make test-native-aarch64
```

Cross execution requires the corresponding compiler, sysroot and runner. The
target gate checks behavior and object details; successful object emission by
itself is not an execution claim.

## Native RISC-V64 output

Select `--target=riscv64-linux-gnu`. The implemented hosted target uses the
LP64D ABI and ELF; argument placement, stack alignment, calls and relocations
follow that target contract.

```sh
build/pslcc-native --target=riscv64-linux-gnu \
  tests/bootstrap_stack_arguments.lisp build/stack-riscv64.o
make test-native-riscv64
```

The focused target gate uses a RISC-V cross compiler and runner when available.
The freestanding RISC-V object path is separately selected with the documented
`none` target/profile combination; it does not acquire hosted runtime support
implicitly.

## Native Windows output

`--target=x86_64-windows-gnu` emits AMD64 COFF objects with Windows ABI and
unwind metadata. The native compiler runs on supported Linux or Windows hosts;
Windows-host linking remains unsupported, while object emission is available.

```sh
build/pslcc-native --target=x86_64-windows-gnu \
  tests/bootstrap_stack_arguments.lisp build/stack-windows.o
make test-native-windows
```

The Windows target gate uses the MinGW toolchain and Wine where configured. It
checks ABI behavior and COFF metadata, including unwind information for the
implemented frame forms.

## Hosted object output

`-c` emits the target object without invoking a final linker. The object may
contain imports for C functions, data or runtime helpers. Inspect those imports
with the platform's object tools, then provide the required C objects/libraries
when linking. A hosted profile permits explicit runtime imports; it does not
silently link an executable when `-c` was requested.

```sh
build/pslcc-native --profile=hosted -c examples/hosted/list.lisp -o build/list.o
```

A freestanding object remains free of implicit libc, GC, hosted startup and OS
dependencies. The selected profile and target are independent choices.

## Hosted source input

The native source loader handles the implemented include form, decodes source
strings, assembles included units in source order and collects ordered
`ffi:source` declarations. Include paths are resolved relative to the declaring
source file, repeated canonical source units are included once, and active
include cycles or malformed input are diagnosed before object publication.

See the [include fixture](../tests/include/native/main.lisp) and the
[C-source example](../examples/ffi/source_import.lisp) for complete inputs.

The host source-unit API returns an owned NUL-terminated source buffer and an
ordered C-source list. Failed loads release partial state. The hosted controller
compiles collected C sources through an explicit process adapter and merges the
resulting object with the PSL object before publishing the final artifact.

## Hosted canonical paths

Canonical path policy belongs to a host-specific source-path unit, separate from
the portable source reader. POSIX and Windows adapters normalize paths according
to their host rules; the source loader uses canonical names for duplicate
inclusion and cycle detection. This is a hosted compiler service and does not
change the target program's OS or object format.

## Further reading

- [Historical component and API notes](../docs/history/native-bootstrap-notes.md)
- [Compiler source organization and pipeline](../docs/architecture.md)
- [Compiler APIs, options and verification](../docs/compiler.md)
- [Implemented language contract](../docs/core.md)
- [M8 status and remaining gates](../docs/roadmap.md)
