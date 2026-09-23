# Portable Systems Lisp engineering roadmap

This roadmap records the larger PSL design as ordered engineering gates. The
[core specification](core.md) records only the implemented language subset. A
milestone is complete only when its documented behavior works through `pslcc`,
its acceptance programs pass, and the [support matrix](#current-support-matrix)
is updated. Dates and staffing are deliberately unspecified.

## Current support matrix

| Capability | State | Evidence or limit |
| --- | --- | --- |
| Stage 0 host | Working | Compiler runs under SBCL. |
| Typed source and macros | Working subset | Ordinary `defun` with type/C-export declarations, host-side `defmacro`, typed scalar and small C-struct values, lexical `let`, calls, and control flow. |
| IR pipeline | M2 complete | Verified typed HIR → CFG/SSA with `phi` joins → verified LIR; `-O1` inlines small pure leaves, folds constants, and removes dead pure values. |
| x86-64 Linux / SysV / ELF64 | M3 complete for documented subset | Integer, pointer, `float`, and `double` values use register and stack locations; `void` results and naturally aligned scalar-field C structs of at most 16 bytes work, including mixed register classes. Larger and packed aggregates, varargs, and `long double` are rejected. |
| x86-64 Windows / Microsoft x64 / COFF | M5 complete for documented subset | Four positional GP/SSE argument registers, shadow space, stack arguments, direct small structs and indirect structs up to 16 bytes, and COFF unwind records. MinGW-w64 links `.exe`, `.a`, and `.dll`; Wine runs the C interoperability corpus. |
| AArch64 Linux / AAPCS64 / ELF64 | M6 complete for documented subset | Self-encoded AArch64 instructions, AAPCS64 GP/FP and stack calls, small C structs including homogeneous float aggregates, ELF call/GOT relocations, GNU cross linking, and QEMU execution. Larger aggregates and varargs remain unsupported. |
| C layout and data symbols | Working on supported hosted targets | `defcstruct` matches C size, alignment, and offsets for supported fields, including LP64 versus LLP64 `long`. ELF uses PIC GOT relocations; COFF uses relative data relocations. |
| Local C source inclusion | Working on supported hosted targets | `ffi:source` compiles a `.c` file with the selected C compiler and merges it into the target relocatable object. |
| Hosted dynamic runtime | M4 complete for documented subset | Versioned 64-bit tagged values, conses, UTF-8 byte strings, symbols, packages, one-argument lexical closures, two values, and a single-threaded mark-and-sweep collector. See the [runtime contract](runtime.md) for limits. |
| Allocation effect checks | Working M4 slice | `without-allocation` checks transitive direct calls; unknown imports and indirect calls fail unless a trusted import effect is declared. |
| x86-64 none / ELF64 | M7 executable subset | Runtime-free static image with an explicit entry or generated `linux-exit` startup, linker script, and map. QEMU user-mode executes the explicit Linux-syscall startup without libc. |
| RISC-V64 Linux / LP64D / ELF64 | M7 complete for documented subset | Self-encoded machine code, GP/FP and stack calls, small C structs, ELF call/GOT relocations, GNU cross linking, and QEMU execution. Larger aggregates, variadics, and `long double` remain unsupported. |
| RISC-V64 none / ELF64 | M7 executable subset | QEMU `virt` image with explicit startup, stack setup, UART access from Lisp, and SiFive Test exit status; no firmware, OS, libc, or hosted runtime is linked. Other boards require their own startup and memory map. |
| Hosted ANSI Common Lisp | Pending M9 | `--profile=hosted` has an M4 managed-value subset; numeric tower, conditions, CLOS, streams, `eval`, and conformance remain pending. |
| Executables and libraries | Working on supported hosted targets | `pslcc` invokes the selected GCC linker for executables and shared libraries, and `ar` for deterministic `.a`; dynamic source selects only required runtime objects. |
| macOS and Wasm | Pending M10 | No object writer or code generation for these targets yet. |

The existing `sh tests/smoke.sh` verifies ELF structure and relocations,
byte-for-byte repeatability, C calls in both directions across GP, SSE, and
stack locations, C layout and data symbols, linked outputs, macros, branches,
lexical bindings, signed comparison, wrapping arithmetic, and absence of hidden
runtime symbols in a standalone object. This is the baseline regression gate
for every subsequent milestone.

## M0 — Core language and profile specification · Complete baseline

**Deliverables**

- Define the hosted and freestanding profiles independently: guaranteed forms,
  allowed runtime capabilities, compile-time host behavior, and diagnostics for
  unavailable features. Keep standard Common Lisp forms semantically compatible
  in the hosted profile; put machine operations in `psl`.
- Specify machine types, literal typing and conversions, wrapping/checked/
  saturating arithmetic, pointer provenance and volatile access, structure
  packing/alignment, storage lifetimes, and effects needed for `no-allocation`.
- Specify compilation stages and cross-compilation rules so host-executed macros
  cannot silently depend on target-only code. Record the public CLI and library
  API as they become implemented.

**Gate:** [the specification](specification.md) states the profile, reader,
macro, machine-value, memory, layout, allocation, and staging rules. Its worked
examples use ordinary Lisp source. [The implemented core](core.md) identifies
the Stage 0 subset; unsupported constructs fail during compilation. The current
subset is exercised by the C harnesses and negative tests. Later milestones
may refine their own facilities without treating them as implemented today.

## M1 — First native object · Complete

**Deliverables**

- Read and expand a typed source subset, build typed HIR and portable LIR, emit
  x86-64 System V machine code, and write ELF64 symbols and relocations without
  requiring an assembler for normal output.
- Support `pslcc -c source.lisp -o output.o`, `--target`, and `--profile` with
  clear errors for unsupported inputs. Keep `psl.compiler:compile-source` usable
  from SBCL as the Stage 0 library entry point.

**Gate:** C invokes a PSL export, PSL invokes a C import, `readelf` recognizes
the object and relocations, two identical builds match byte for byte, and a
source file with no imports has no undefined runtime symbols. `sh tests/smoke.sh`
passes this gate on x86-64 Linux; later milestones broaden the language.

## M2 — Compiler foundation and optimization · Complete

**Dependencies:** M1 and the applicable M0 semantics.

**Deliverables**

- Add a verifier for typed HIR and LIR, source-linked diagnostics, and IR dump
  modes for debugging. Define the target/backend contract in terms of LIR,
  calling convention, relocations, and object format.
- Introduce control-flow graphs and SSA with explicit joins. Add small,
  independently testable passes for constant folding, dead-code elimination,
  and simple inlining; preserve effects and volatile operations.
- Keep architecture and OS facts in target descriptions and backends. Add
  compiler-library calls for reading, analyzing, lowering, and object emission
  without routing through the CLI.

**Gate:** IR verification rejects malformed programs before code generation;
optimized and unoptimized programs agree on behavior; object output remains
deterministic; the x86 backend consumes only target-independent LIR plus target
metadata, never raw source forms.

The [pipeline contract](compiler.md) records the library stages and IR
invariants. `sh tests/smoke.sh` runs C harnesses at both optimization levels,
checks object repeatability, rejects malformed HIR/SSA/LIR, and inspects the
expected optimization and effect behavior.

## M3 — Complete the first C ABI path · Complete for documented subset

**Dependencies:** M1; use the M2 verifier as it becomes available.

**Deliverables**

- Implement remaining System V AMD64 parameter and return locations, including
  stack arguments, supported floating-point classes, and documented aggregate
  cases. Define C integer aliases according to the selected target ABI.
- Add `psl:defcstruct` with C-compatible field offsets, alignment, and size;
  add import/export declarations for data and functions and position-independent
  relocations needed by shared objects.
- Extend the driver to invoke conventional linkers and archivers for native
  executables, static libraries, and shared libraries. Keep `-c` independent of
  those tools and keep link inputs explicit.

**Gate:** C and PSL call each other across register and stack boundaries;
generated C layouts match a C compiler's `sizeof`, `_Alignof`, and `offsetof`;
an executable, `.a`, and `.so` are consumed by an ordinary C build. The test
suite inspects exported symbols and rejects hidden PSL runtime dependencies.

`sh tests/smoke.sh` passes this gate on x86-64 Linux at `-O0` and `-O1`.
It runs C↔PSL integer and floating calls, small C-struct returns and stack
fallback (including mixed register classes), C layout comparisons, data
import/export through PIC relocations, and executable/archive/shared-library
builds. `readelf` and `nm` check the
objects and exported/undefined symbols; repeated object, archive, and shared
library builds are byte-identical. The supported aggregate cases are naturally
aligned C structs of one or two eightbytes composed of integer, pointer, `float`, and
`double` fields. Larger aggregates, packed aggregates by value, variadic
calls, and `long double` remain unsupported and are documented in
[the implemented core](core.md); they are not silently lowered
with an incompatible convention.

## M4 — Modular dynamic Lisp runtime · Complete for documented subset

**Dependencies:** M0 object semantics, M2 effect information, M3 linker path.

**Deliverables**

- Define a 64-bit hosted object representation and stable interfaces for
  values, roots, allocation, and runtime calls. Add symbols, conses, strings,
  lexical closures, multiple values, and packages in modules with explicit
  dependency edges.
- Start with a correct stop-the-world mark-and-sweep collector; keep the
  collector out of typed programs that never request managed objects. Add
  separate startup and platform modules rather than embedding OS calls in the
  language frontend.
- Add call-graph/effect checking for allocation-free regions. An unknown call
  must prevent an allocation-free guarantee until its effects are declared or
  proven.

**Gate:** dynamic-value programs run under the hosted profile, collector tests
cover reachable and unreachable objects, module-selection tests show unused GC
and dynamic modules absent from typed binaries, and allocation-free violations
fail at compile time.

The [runtime contract](runtime.md) defines the tagged representation, root
interface, module dependencies, and hosted source limits. `sh tests/smoke.sh`
runs list, string/package, closure, and multiple-value programs at `-O0` and
`-O1`; it checks selected runtime symbols, two separately compiled closure
objects linked together, static and shared linking, typed
binary exclusion, and allocation-effect diagnostics. `sh tests/runtime.sh`
exercises reachable and unreachable objects through the collector and checks
the C runtime ABI. Direct string literals and captured lexical values work;
closure calls currently accept one argument, and multiple-value binding
currently accepts two values from a direct `values` form. General Common Lisp
behavior remains the M9 goal.

## M5 — Second operating system: x86-64 Windows · Complete for documented subset

**Dependencies:** M2 target boundary and M3 ABI/linking tests.

**Deliverables:** implement Microsoft x64 calls, PE/COFF objects and
relocations, Windows startup/platform bindings, and target-specific library
selection while reusing the frontend and generic IR passes.

**Gate:** a Windows runner links and executes C↔PSL tests, checks C data layout,
and inspects COFF symbols/relocations. Changes to the reader, macro expander,
or generic optimizer are not required merely to add this target.

`sh tests/windows.sh` compiles with `--target=x86_64-windows-gnu`, links with
MinGW-w64, and runs under Wine at `-O0` and `-O1`. It checks C calls in both
directions across positional GP/SSE and stack arguments, C structs passed by
register or reference (including a 12-byte copy), LLP64 layout, data
imports/exports (including functions and data imported from separate C DLLs), `ffi:source`,
static archives, DLLs, and hosted runtime
programs. `objdump` checks COFF symbols and relocations;
`RtlLookupFunctionEntry` checks linked unwind registration. Repeated `.o`, `.a`, `.dll`, and `.exe`
builds match byte for byte. The Windows platform module supplies stack bounds
for the single-threaded collector. Larger aggregates, varargs, and
`long double` remain unsupported, as on the documented Linux subset.

## M6 — Second architecture: AArch64 Linux · Complete for documented subset

**Dependencies:** M2 backend contract and M3 C test corpus.

**Deliverables:** implement AArch64 instruction selection/encoding, register and
stack allocation, AAPCS64 calls, ELF64 AArch64 relocations, and target layout.
Reuse the same typed source, HIR, and LIR validation.

**Gate:** native or QEMU AArch64 execution passes the portable arithmetic,
control-flow, and C interoperability corpus; object inspection shows the
expected AArch64 machine and relocation types.

`sh tests/aarch64.sh` runs the shared typed and hosted programs under QEMU at
`-O0` and `-O1`. It checks C calls in both directions, register and stack
arguments, LP64 layout, imported and exported data, `ffi:source`, small C
structs, homogeneous float aggregates with nested fields, and exhausted
floating registers. The suite checks ELF machine and call/GOT relocations,
byte-for-byte repeatable objects, archives, and shared libraries,
and runtime-module exclusion. The compiler emits AArch64 machine words and
ELF64 objects directly. GNU tools are used to compile C and link artifacts;
QEMU is used only to execute cross-target tests. C structs larger than 16
bytes, variadic calls, and `long double` remain outside the supported subset.

## M7 — Freestanding execution and RISC-V · Complete for documented subset

**Dependencies:** M0 freestanding rules, M2 backend contract, M3 link control.

**Deliverables**

- Finish x86-64 `none` startup, entry-point export, static layout/linker-script
  handling, and a QEMU program that runs with no libc or PSL runtime symbols.
- Add RISC-V64 Linux with its selected ABI and ELF relocations, then RISC-V64
  bare metal with a minimal device or emulator output path. Keep macro
  execution on the build host throughout cross compilation.

**Gate:** QEMU executes both freestanding proofs; link maps show only selected
objects; cross compilation succeeds from x86-64 without running target code
during the build.

`sh tests/riscv64.sh` compiles the shared typed, C interoperability, native,
and hosted examples for RISC-V64 Linux at `-O0` and `-O1`, then runs them under
QEMU user-mode. It checks LP64D register/stack edges, ELF machine flags and
call/GOT relocations, repeatable objects and libraries, and runtime-module
selection. The compiler writes RISC-V instructions and ELF objects itself;
GNU tools only compile C and link artifacts. The same suite builds an x86-64
static image with the explicit `linux-exit` syscall startup and a RISC-V64
bare-metal image with the `qemu-virt` startup. QEMU executes both. It inspects
undefined symbols, dynamic dependencies, and link maps; checks explicit entry
and linker-script selection; runs a host-expanded macro program on RISC-V; and
verifies UART output and success/failure exit through QEMU's SiFive Test device.
The RISC-V image uses QEMU `virt` with 128 MiB RAM and `-bios none`. The x86-64
proof intentionally uses Linux user-mode emulation and an explicit exit syscall;
an x86-64 kernel or board startup is outside this slice.

## M8 — Self hosting · Pending

**Dependencies:** enough M4 language/runtime support to express the compiler,
plus stable M2 compiler-library interfaces.

**Deliverables:** port compiler modules to PSL incrementally, build Stage 1
with SBCL Stage 0, build Stage 2 with Stage 1, then build Stage 3 with Stage 2.
Retain a documented bootstrap path from a fresh checkout.

**Gate:** successive stages pass the same source/object/interop corpus and
produce equivalent compiler behavior; deterministic outputs are compared where
the bootstrap representation permits bit-for-bit matching.

## M9 — Hosted ANSI Common Lisp completion · Pending

**Dependencies:** M4 dynamic runtime and a self-host-capable compiler core.

**Deliverables:** complete the reader, packages, dynamic bindings, exact numeric
tower, arrays and sequences, conditions and restarts, streams, CLOS, `eval`,
compiler functions, and interactive loading. Add a REPL and debugger support
after those semantics work as library APIs. Explicit PSL machine operations
must not change the meaning of standard Common Lisp forms.

**Gate:** run and publish results from a documented ANSI Common Lisp
conformance suite, review uncovered requirements against the standard, and
exercise interactive redefinition and `eval`. Do not label the hosted profile
ANSI conforming while known required behavior is missing.

## M10 — Further targets and advanced capabilities · Pending

**Dependencies:** stable M2 interfaces and the relevant earlier runtime/ABI
work. Deliver these as separately gated projects, not one release switch.

- Mach-O/macOS: object writer, platform ABI integration, C interop, and runner.
- WebAssembly: wasm32/wasm64 lowering, module writer, imported host functions,
  and runtime-profile definition.
- Advanced execution: atomics with memory-order semantics, SIMD with scalar
  fallback where specified, threads, richer debug information, additional GC
  strategies, hot replacement, and performance work measured against equivalent
  C kernels.

Each target or capability graduates only with its own executable tests,
support-matrix entry, and documented limitations. No empty backend or runtime
directory is a milestone deliverable.
