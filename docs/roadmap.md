# Portable Systems Lisp engineering roadmap

[Documentation](README.md) / Roadmap

**Current milestone: M8 self hosting, in progress.** A milestone closes when
its acceptance gates pass through the real compiler and its support claims are
updated. The [implemented contract](core.md) describes current semantics; the
[language design](specification.md) also includes future work.

- [Current support](#current-support-matrix)
- [Milestone overview](#milestone-overview)
- [M8 release requirements](#m8--self-hosting--in-progress)
- [M9 Common Lisp completion](#m9--hosted-ansi-common-lisp-completion--pending)
- [M10 further targets](#m10--further-targets-and-advanced-capabilities--pending)
- [Implementation history](history/milestone-notes.md)

## Current support matrix

| Area | Implemented behavior | Limit or verification |
| --- | --- | --- |
| Seed compiler | `./pslcc` runs under SBCL | Trusted source macros execute on the build host |
| Native compiler | Eight compiled PSL units own reading, analysis, IR, encoding, objects, driver and diagnostics | Complete fresh Stage 1–3 release remains open |
| Typed language | Declared functions, machine integers, pointers, control flow, explicit C boundaries | See [source forms](core.md#source-forms) |
| IR and optimization | Verified HIR → SSA → LIR; baseline `-O0` and optimizing `-O1` | Verification stays in the compilation path |
| Hosted runtime | Tagged values, conses, strings, symbols, packages, closures, two values, VALUE vectors and GC | Managed subset, not ANSI Common Lisp |
| Allocation effects | Transitive direct-call checks for `without-allocation` | Unknown calls require a trusted effect declaration |
| x86-64 Linux | System V ABI, ELF64, object and linked output | Native execution and C interop |
| x86-64 Windows | Microsoft x64 ABI, COFF, unwind metadata and MinGW-w64 links | Wine execution; native Windows compiler host supports object output |
| AArch64 Linux | AAPCS64, ELF64 and GNU cross links | QEMU user-mode execution and C interop |
| RISC-V64 Linux | LP64D, ELF64 and GNU cross links | QEMU user-mode execution and C interop |
| x86-64 none | Static ELF64 with explicit startup and linker path | Linux user-mode execution via explicit `linux-exit` startup |
| RISC-V64 none | Explicit startup, memory map, UART and test-device exit | QEMU `virt`, no firmware or OS |
| C layouts and calls | Scalars and naturally aligned scalar-field records through 16 bytes | Packed/large by-value records, varargs and `long double` are excluded |
| C source and artifacts | Explicit `ffi:source`, executable/static/shared links on the Linux compiler host | Output toolchain selected independently from compiler host |
| macOS and WebAssembly | Planned | No implemented backend/object writer yet |

Object output alone is not an execution claim. A profile selects source and
runtime capabilities independently from architecture, ABI, OS, and object
format. Exact restrictions belong in [core.md](core.md), rather than being
inferred from a target name.

## Milestone overview

| Milestone | State | Acceptance boundary |
| --- | --- | --- |
| M0 · Core specification | Complete baseline | Profiles, staging, machine extensions, memory and portability semantics documented |
| M1 · First native object | Complete | PSL encodes and writes a callable x86-64 ELF object |
| M2 · Compiler foundation | Complete | Verified HIR/SSA/LIR, reusable APIs, optimization and negative tests |
| M3 · First C ABI | Complete for documented subset | Bidirectional C calls, layouts, data, object inspection and linked artifacts |
| M4 · Hosted runtime | Complete for documented subset | Explicit runtime modules, managed values, roots and allocation checks |
| M5 · Windows | Complete for documented subset | Microsoft x64/COFF, MinGW-w64 links and Wine interop |
| M6 · AArch64 | Complete for documented subset | PSL encoding, AAPCS64/ELF64 and QEMU interop |
| M7 · Freestanding and RISC-V | Complete for documented subset | LP64D interop and explicit executable freestanding proofs |
| M8 · Self hosting | **In progress** | Complete compiler generations and full corpus reach a fixed point |
| M9 · Hosted ANSI Common Lisp | Pending | Published conformance gate and interactive semantics |
| M10 · Further targets and capabilities | Pending | Separate executable gates for each addition |

Earlier component evidence and original milestone deliverables are retained in
[the implementation notes](history/milestone-notes.md). Remaining-work statements
there are historical. This page and the implemented contract describe the
current integrated state.

## M8 — Self hosting · In progress

M8 replaces the SBCL-hosted implementation as the running compiler while
retaining a documented bootstrap seed. Stage 1 is built by Stage 0, Stage 2 by
Stage 1, and Stage 3 by Stage 2, from the same complete source manifest.

### Implemented components

- Source spelling and identities, ordered packages/includes, and bounded
  native macro expansion run in the compiler-host environment.
- Typed analysis, effects, HIR/SSA/LIR verification, optimization, CPU encoding,
  and ELF/COFF writing live in PSL modules.
- The native driver owns source assembly, allocation, cleanup, CLI behavior,
  diagnostics, object publication, runtime selection and linked artifacts.
- Macro definitions and bindings use managed VALUE vectors through rooted
  handles. Syntax, identity and IR records retain explicit typed arena ownership.
- Focused gates cover hosted runtime operations, small aggregate ABIs,
  closures, function addresses, cross-target objects and freestanding startup.
- Component generation comparisons reproduce deterministic objects. These
  results support those components; they do not establish the full release.

### Remaining work

The macro evaluator now covers the bounded list/integer predicates found by
source preaudits, including canonical NIL equality. Focused gates compare these
behaviors with Stage 0. Hosted CLI capacity for very short valid sources remains
under validation, along with the complete source inventory, release wiring and
fresh integrated proof.

M8 closes only after all of the following pass on one frozen source snapshot:

1. Record the seed, toolchain, every compiler input, generation unit and test
   owner. Include every test and example; state why any input needs a
   surrounding API or include gate.
2. Build all eight native PSL units freshly for Stage 1, Stage 2 and Stage 3.
   Generation builds must not substitute cached fixture objects.
3. Compare seed/native acceptance and rejection at `-O0` and `-O1` across all
   12 declared target/profile cells. Keep the complete example inventory.
4. Run the same object, IR, diagnostics, managed runtime, C interop, CLI,
   negative-source and cross-target execution gates against each generated
   compiler and its own objects.
5. Compare observable linked behavior, native-stage IR and diagnostics, and
   deterministic Stage 2/3 object and executable bytes.
6. Update support claims and preserve the manifest, reports and known limits.

The frontend must keep target details out of portable IR. Macro execution
stays on the build host. Compiler output uses PSL's encoders and object writers;
C compilers, linkers, inspectors and emulators remain boundary tools. The
[architecture](architecture.md) maps these responsibilities.

Passing this gate establishes self hosting for the documented compiler and
corpus. ANSI Common Lisp conformance requires M9.

## M9 — Hosted ANSI Common Lisp completion · Pending

Complete the reader, packages, dynamic bindings, exact numeric tower, arrays
and sequences, conditions and restarts, streams, CLOS, `eval`, compiler
functions and interactive loading. Add REPL/debugger support through the same
library interfaces. PSL machine operations must preserve standard Common Lisp
meanings.

**Gate:** publish results from a documented ANSI Common Lisp conformance suite,
review uncovered requirements, and exercise interactive redefinition and
`eval`. Do not claim conformance with known required behavior missing.

## M10 — Further targets and advanced capabilities · Pending

Each addition needs its own implementation, executable evidence and support
entry:

- Mach-O/macOS: object writer, platform ABI, C interop and runner.
- WebAssembly: lowering, module writer, host imports and runtime profile.
- Execution and tooling: atomics and memory ordering, SIMD, threads, richer
  debug information, additional GC strategies, hot replacement and measured
  performance work.

Empty directories and CLI switches do not complete a target or capability.
