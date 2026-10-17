# Compiler source organization

[Documentation](README.md) / Architecture

This page maps compiler ownership and the two compiler implementations. For the
implemented language contract, see [core](core.md); for milestone status and
remaining work, see [roadmap](roadmap.md). The native bootstrap reference is in
[`bootstrap/README.md`](../bootstrap/README.md), and API-level pipeline details
are in [`compiler.md`](compiler.md).

## Compiler stages

Stage 0 is the seed compiler. Its command-line entry point is `pslcc`, and its
hosted implementation is loaded from `src/load.lisp`. The native compiler is
compiled PSL hosted by a small C boundary; it can compile the eight declared
PSL compiler units listed below. A successful native compiler build does not
by itself establish a fresh Stage 1–3 release or complete M8 corpus pass. Those
release checks remain open.

Both implementations follow the same broad compilation flow:

```text
source units
    → read, identify names, collect declarations and expand macros
    → typed HIR and HIR verification
    → CFG/SSA lowering and SSA verification
    → optional optimization and post-optimization verification
    → LIR lowering and LIR verification
    → target instruction encoding and fixup patching
    → ELF or COFF object writing
    → optional explicit C toolchain and runtime linking
```

The frontend owns source meaning. HIR, SSA and LIR are target-independent.
Target selection supplies architecture, ABI, operating system and object
format as separate facts. CPU backends encode instructions; object modules
write relocations and sections. A conventional C compiler and system linker
are invoked only at explicit C-source or final-link boundaries.

## Stage 0 source tree

`src/cli.lisp` parses command-line options and calls the reusable compiler
interface in `src/driver.lisp`. `src/load.lisp` loads modules in dependency
order, and `src/package.lisp` declares package names and exports.

| Area | Owner | Responsibility |
| --- | --- | --- |
| Frontend | `src/frontend/` | Reading, package and symbol identity, source macros, typed analysis, effects, closures, strings and runtime requests. |
| Portable IR | `src/ir/` | HIR, SSA, LIR, type catalogues, optimizers, root lowering, verifiers and stable dumps. |
| CPU backends | `src/backend/` | x86-64, AArch64 and RISC-V64 instruction encoding, ABI locations, root frames and fixups. |
| Object formats | `src/object/` | ELF64 and COFF symbols, sections, relocations and Windows unwind data. |
| Target contract | `src/target.lisp` | Independent architecture, ABI, OS and object-format selection. |
| Toolchain boundary | `src/ffi/` | Explicit C-source compilation, runtime closure, final linking and freestanding startup. |
| Hosted runtime | `runtime/` | Managed values, precise roots, collections, strings, symbols, packages, closures, vectors and startup. |

The Stage 0 implementation is Common Lisp loaded under SBCL. Its reusable
compiler API is separate from CLI parsing. The compiled native implementation
exposes typed entry points through its C ABI.

## Native compiler units

The native compiler is built from eight hosted PSL units. Their boundaries keep
core compilation separate from the host controller and its I/O adapters.

| Unit | PSL source root | Responsibility |
| --- | --- | --- |
| Core | `bootstrap/native-core.lisp` | Reader, source semantics, macro expansion, typed analysis, IR, optimization, CPU backends and object writers. |
| Host driver | `bootstrap/host/driver.lisp` | Owned driver/storage lifecycle, context initialization and compilation coordination. |
| Source unit | `bootstrap/host/source_unit.lisp` | Include traversal, C-source collection, canonical file ownership and assembled source. |
| Input | `bootstrap/host/source_io.lisp` | Incremental hosted file input. |
| POSIX paths | `bootstrap/host/source_path_posix.lisp` | Canonical source paths on the Linux compiler host. |
| Compiler controller | `bootstrap/host/compiler.lisp` | CLI and library entry points, source loading, growth retries, output publication and cleanup. |
| Output | `bootstrap/host/output.lisp` | Hosted object and linked-artifact output. |
| Diagnostics | `bootstrap/host/diagnostics.lisp` | Phase selection and source/compiler diagnostics. |

`bootstrap/native-core.lisp` includes the compiler implementation as one
translation unit so internal PSL calls stay ordinary calls. `bootstrap/driver.c`
provides the process entry trampoline. `bootstrap/native_api.h` is the shared C
boundary; `*_types.lisp` files declare record layouts, while implementation
logic remains in PSL. `bootstrap/host/platform_stdio.c` and
`bootstrap/host/platform_toolchain.c` provide primitive host operations.

The native source loader and controller are separately compiled units because
they own filesystem traversal, persistent driver storage and command-line
execution. Their runtime dependencies belong to the hosted compiler process;
they do not silently change a user's selected output profile.

## Pipeline and representations

The native and Stage 0 pipelines preserve the same module separation:

| Stage | Representation and checks | Owner |
| --- | --- | --- |
| Source collection | Source identities, package actions, macro registrations and ordered C inputs | `frontend/` and the host source unit |
| Analysis | Typed HIR with source references and explicit effects | `frontend/` |
| HIR | Structural, type, source, lexical-scope and closure metadata validation | `ir/` verifiers |
| SSA | Basic blocks, typed values, explicit branches and PHI joins | `ir/` |
| Optimization | Verified inlining, folding, branch pruning, compaction and liveness | `ir/` |
| LIR | Virtual registers, labels, edge copies, root operations and fixups | `ir/` |
| Encoding | Target instruction bytes/words and call/address fixups | `backend/` |
| Object writing | ELF or COFF symbols, sections, relocations and metadata | `object/` |

HIR and SSA retain source/type facts needed by later verifiers. Backends accept
verified LIR and receive an explicit target contract; they do not inspect
source syntax. Object writers consume encoded functions and fixups, not Lisp
forms. Verification runs before and after optimization and before backend
encoding, including checks on externally supplied IR records.

## Runtime and memory boundaries

Managed runtime use is explicit. In hosted source, runtime imports determine a
transitive runtime-module closure; the selected linker adds only those modules
and their declared dependencies. Freestanding output remains free of implicit
libc, GC, hosted startup and operating-system dependencies. Compiler-host
runtime services and the requested target program's profile are separate
choices.

The runtime modules divide responsibility as follows:

| Module | Responsibility |
| --- | --- |
| `value.c` | Tagged `VALUE` representation and fixnums. |
| `cons.c`, `string.c`, `symbol.c`, `package.c` | Managed sequence, text and namespace objects. |
| `closure.c` | Precise lexical closure environments and calls. |
| `vector.c` | Managed mutable `VALUE` vectors. |
| `values.c` | Multiple-value runtime support. |
| `gc.c` | Heap management and explicit precise roots. |
| `startup.c` | Hosted runtime initialization. |
| `platform_linux.c`, `platform_windows.c` | Host stack bounds and platform support selected for the runtime. |

The compiler's syntax, IR and object buffers are typed caller-owned arenas.
The native macro registry uses managed vectors through opaque runtime handles;
its values remain rooted by the runtime while AST and IR records keep their
ordinary typed layouts. The C boundary exposes ownership explicitly: `ffi:source`
includes C source, `ffi:import-function` declares a C signature, and `ffi:call`
invokes that import.

## Target and ABI boundaries

Architecture, ABI, OS and object format are independent selectors. The current
hosted native object targets are x86-64 Linux ELF, x86-64 Windows COFF, AArch64
Linux ELF and RISC-V64 Linux ELF. x86-64 none and RISC-V64 none support the
documented freestanding object/static-link paths. Emitting an object does not
mean that a target is executable on the current host.

`backend/` owns instruction encodings and ABI argument/result locations.
`object/` owns format-specific sections, symbols, relocations and unwind data.
`target.lisp` selects their combination. `src/ffi/` and the native host adapter
invoke installed C compilers, linkers and archivers when the requested operation
requires them. Test harnesses invoke target runners. Lisp code generation uses
PSL encoders and writers without an external assembler or third-party
code-generation library.

## Verification entry points

Run `sh tests/smoke.sh` after compiler changes. Focused `tests/bootstrap_*.sh`
gates compare Stage 0 and native behavior, inspect objects or exercise
caller-owned APIs as appropriate. `tests/bootstrap_native_compiler.sh` covers
the native compiler's source, verifier, output and receiver interfaces; target
scripts add their own C harness, object inspection and runner checks. The
complete fresh Stage 1–3 build and corpus proof remains the M8 acceptance gate;
component gates are evidence for their named slice, not a substitute.

## More detail

- [Compiler APIs and pipeline invariants](compiler.md)
- [Implemented language contract](core.md)
- [Milestones and open work](roadmap.md)
- [Native bootstrap build, CLI and focused verification](../bootstrap/README.md)
