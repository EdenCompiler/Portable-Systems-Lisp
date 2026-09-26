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
| Self hosting | M8 in progress | Native PSL modules cover scanning, parsing, integer atoms, C structure layout, typed function signatures, arenas, byte emission, verified typed HIR/SSA/LIR, x86-64 encoding, and ELF writing for several functions. A restricted compiler handles integer/pointer signatures, memory, loops, casts, conditionals, and recursion and directly compiles integer rules, byte-emitter, arena, integer reader, and scanner modules. Stage 1–3 and the full corpus gate remain open. |
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

## M8 — Self hosting · In progress

**Dependencies:** enough M4 language/runtime support to express the compiler,
plus stable M2 compiler-library interfaces.

**Deliverables:** port compiler modules to PSL incrementally, build Stage 1
with SBCL Stage 0, build Stage 2 with Stage 1, then build Stage 3 with Stage 2.
Retain a documented bootstrap path from a fresh checkout.

**Gate:** successive stages pass the same source/object/interop corpus and
produce equivalent compiler behavior; deterministic outputs are compared where
the bootstrap representation permits bit-for-bit matching.

**Bootstrap subgates**

1. Port source spelling, packages, includes, and compile-time macro execution
   so the native reader accepts every compiler module. Keep macro execution on
   the build host during cross compilation.
2. Port typed analysis, HIR/SSA/LIR construction and verification, effects,
   and the generic optimization passes. Compare each stage's IR and diagnostics
   on the same accepted and rejected source corpus.
3. Port instruction encoders and ELF/COFF writers with local/global symbols,
   data, relocations, and ABI calls. Lisp object output must not invoke LLVM or
   an external assembler; C input and final links use the selected toolchain.
4. Port the compiler driver and enough runtime services for source loading,
   memory, strings, collections, and diagnostics. Build a native Stage 1 that
   compiles its own complete source, including the driver.
5. Use Stage 1 to build Stage 2 and Stage 2 to build Stage 3. Run the same
   object inspection, C interop, cross-target, and negative-source corpus with
   all three stages. Compare diagnostics and linked behavior, then compare
   generated object bytes wherever the bootstrap format is deterministic.

The first ported components are the byte emitter, arena, scanner, parser,
integer-atom reader, and first ELF64 writer slice in `bootstrap/`. Compiled
PSL emits and patches little-endian bytes, manages caller-owned storage, scans
source bytes, and builds a caller-owned syntax tree. The `tests/bootstrap_binary.sh`,
`tests/bootstrap_reader.sh`, `tests/bootstrap_parser.sh`, and
`tests/bootstrap_component.sh` scripts run at `-O0` and `-O1` on each hosted
target, check repeatable objects, and accept a target triple as an argument.
The binary test compares bytes against the Stage 0 module; the reader and
parser tests check token/tree structure and traverse the example corpus on
Linux targets.
The source subset now has local helper functions, typed bit extraction,
wrapping integer casts, a Boolean `while` loop, and source inclusion.
`sh tests/bootstrap_modules.sh` builds the combined native unit and checks
relative source and C-file paths from included modules.
`sh tests/bootstrap_elf64.sh [TARGET]` compares a native PSL-written object
byte for byte with Stage 0's object for a single exported function, then links
and runs it with C. This passes for x86-64, AArch64, and RISC-V64 ELF64 without
executing target code during object generation. A separate native writer now
emits multiple x86-64 function symbols. Relocations, data, and COFF remain to
be ported.
`sh tests/bootstrap_native_compiler.sh [HOST_TARGET]` builds a native executable from PSL
compiler components plus a temporary C file-I/O wrapper. It parses a source
file, accepts machine-integer functions with independently typed parameters,
range-checked literals, raw pointer signatures, nested binary wrapping arithmetic, `bits-and`,
U64 `shr64`, explicit integer casts, typed `let` and `progn`, comparisons,
Boolean literals, `if`, test-and-body `cond` clauses, and calls across
the source file, including recursion. It writes an x86-64 ELF object through
verified native HIR → typed CFG/SSA → flat LIR, and links that output to a C caller. It rejects source
outside that slice.
x86-64 System V calls use all six integer argument registers and place later
integer/pointer arguments in aligned outgoing stack areas. A C harness checks
seven-, eight-, and nine-argument calls, narrow signed stack values, pointer
stack values, nested and recursive calls, and source-order argument effects.
Stage 0 and native outputs pass the same C harness; repeat builds, different
host builds, and `-O0`/`-O1` bootstrap builds yield identical native objects.
The native scalar path now covers unsigned and signed 8-, 16-, 32-, and 64-bit
integers, `usize`, `isize`, and the `c-int` alias. Each HIR node retains its source
type; a source-type verifier checks parameter and call signatures, operator
types, casts, and literal representations. It checks literal ranges, narrow
wrapping, input extension, signed comparison, heterogeneous locals, and the
Common Lisp truth rule that integer zero is true.
The native compiler directly compiles the real `bootstrap/ir/integer_types.lisp`
module, which provides width and representation rules used by its analyzer and
verifier. Object inspection finds no unresolved symbols; C checks match Stage 0
behavior, and repeat builds and `-O0`/`-O1` bootstrap builds produce identical
objects for that module.
The native memory slice also directly compiles `bootstrap/binary.lisp`,
`bootstrap/arena.lisp`, `bootstrap/frontend/atoms.lisp`, and `bootstrap/frontend/reader.lisp`. It implements raw pointer
parameters and returns, nested pointer and field types, element-scaled
`pointer+`, signed/unsigned integer and pointer loads and stores, explicit
pointer casts and address construction, and Boolean `while`. Source-type
verification checks pointees, field ownership and offsets, memory widths, and
call signatures. C harnesses compare behavior with Stage 0, scan the example
corpus, and inspect object symbols. Negative fixtures check mismatched types
and malformed memory and loop forms; HIR mutation tests check widths, pointee
references, and pointer arithmetic metadata. Repeat builds, different host
builds, and `-O0`/`-O1` compiler builds produce identical native module objects.
C programs also compare Stage 0 and native behavior for mixed integer signatures
and casts; repeat builds and
`-O0`/`-O1` bootstrap builds produce identical native objects. Packages,
test-only `cond` clauses, and general macro expansion still need a broader
frontend.
The updated native slice runs on x86-64 Linux and Windows/Wine hosts and
produces byte-identical x86-64 objects. Stage 0 also cross-compiles the combined
native unit to AArch64 and RISC-V64 objects. The test script supports execution
on those hosts when their cross compilers and runners are available.

The native default pipeline now lowers the entire documented integer/pointer
subset through typed SSA and flat LIR. It represents conditional PHIs, loop
backedges, source-order effects, and lexical aliases explicitly. SSA checks
references, instruction ownership, terminators, type relationships, PHI
predecessor coverage, and dominance. LIR lowering resolves PHIs with edge
copies, including explicit branch-edge labels. Its verifier checks the flat
CFG and definitions on every incoming path before machine encoding. The
x86-64 backend consumes only LIR, its type catalog, and encoded symbol/fixup
metadata; the old HIR-to-machine encoders have been removed. C mutation tests
reject wrong PHI edges, non-dominating uses, malformed targets, omitted copies,
and undefined registers. Native modules now follow `frontend/`, `ir/`,
`backend/`, and `object/` ownership. Generic optimization and effects, the full
source corpus, remaining ABI/backend/object features, and Stage 1–3 remain
open; this is progress on subgate 2, not completion of M8.

Native source loading now accepts top-level includes. The PSL frontend
recognizes include syntax and decodes Lisp string filenames; a temporary C
host module reads files, resolves canonical paths, preserves include order,
deduplicates repeats, and rejects cycles. Tests compare nested/repeated include
objects with a flattened unit and reject missing files, malformed includes,
and reader errors. File traversal still needs to move into PSL.

The native compiler now compiles every module included by its own
`bootstrap/native-core.lisp`. `sh tests/bootstrap_self_core.sh` builds three
successive native core generations on x86-64 Linux, compiles the full core
without external tool lookup, runs the complete native subset suite on each
generation, and compares their native-generated core and fixture objects byte
for byte. Core objects have no unresolved symbols; rejected-source diagnostics
match exactly across generations. Signature/layout tables no longer have
the old 256-entry ceiling, and the ELF writer permits the complete core.
The same temporary C driver and source loader are linked to each generation.
This is a core reproduction gate; the broader Stage 0 corpus, native optimizer
and effects, remaining target/ABI/object features, and PSL driver/source loader
are still open. Full Stage 1, Stage 2, and Stage 3 compiler builds remain open,
as does the M8 gate.
The scalar source path accepts lowercase hyphenated internal function and local
names; C exports still require C-compatible names. Its deterministic object
test checks both the local ELF symbol and a C caller.
The native source pass now registers simple `defcstruct` declarations. The
bootstrap test compares their size, alignment, and field offsets with C on
each hosted test target. Native function bodies support integer and pointer
access through these layouts; floating accesses, pointer qualifiers, `void`
pointers, and structure values still need a broader native implementation.
It also records typed `defun` signatures in source order. The signature test
parses the byte emitter, arena, integer reader, and scanner modules and checks
their resolved parameter and return shapes. Scalar body compilation consumes
the same signature records and accepts declarations in different clause orders
and multiple body forms. The native body compiler still accepts only the documented integer/pointer
subset; the signature pass does not make Stage 1 viable.

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
