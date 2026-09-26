# Compiler source organization

The Stage 0 compiler keeps the command-line entry point thin and loads modules
in dependency order:

```text
src/
  cli.lisp              command-line parsing
  load.lisp             ordered module loading
  package.lisp          public PSL names and compiler package
  common.lisp           shared diagnostics
  binary.lisp           little-endian byte-buffer operations
  target.lisp           architecture, ABI, OS, and object-format selection
  driver.lisp           compilation pipeline entry point
  frontend/
    layout.lisp         packed structure layout and field lookup
    reader.lisp         source input, declarations, machine types
    runtime.lisp        hosted operations and module requests
    closures.lisp       lexical capture and closure functions
    strings.lisp        hosted UTF-8 source literals
    multiple-values.lisp  two-value source forms
    analyze.lisp        macro expansion and typed semantic analysis
    effects.lisp        transitive allocation-effect checking
  ir/
    hir.lisp            typed HIR data structures
    types.lisp          machine type queries and pointer qualifiers
    ssa.lisp            portable CFG, SSA values, and explicit joins
    lower.lisp          typed HIR to SSA and SSA to portable LIR
    verify/             HIR, SSA, and LIR invariant checks
    optimize.lisp       inlining, constant folding, and dead-code removal
    dump.lisp           stable, readable IR inspection
  backend/
    common.lisp         encoded functions and relocation records
    x86-64.lisp         LIR to x86-64 machine code and ABI argument mapping
    win64-abi.lisp      Microsoft x64 calls, returns, and shadow space
    aarch64.lisp        LIR to AArch64 instructions and AAPCS64 calls
    riscv64.lisp        LIR to RISC-V64 instructions and LP64D calls
  object/
    elf64.lisp          ELF sections, symbols, and relocations
    coff.lisp           COFF sections, symbols, relocations, and unwind records
  ffi/
    toolchain.lisp      C source and selected runtime module linking
    freestanding.lisp   static links, startup selection, and linker scripts
linker/
  riscv64-virt.ld       QEMU virt RAM layout
  x86_64-linux-user.ld  static x86-64 Linux user-mode layout
bootstrap/
  native-core.lisp      source unit including the ported compiler components
  binary.lisp          caller-owned byte emission and patching
  arena.lisp           caller-owned aligned allocation
  compile_scalar.lisp  native analysis, verification, and lowering coordinator
  driver.c             temporary host file-I/O and storage wrapper
  native_api.h         C host boundary for the compiled PSL modules
  host/
    source.c, source.h temporary file reads, path resolution, and source traversal
  frontend/
    reader.lisp, parser.lisp, atoms.lisp, source.lisp
                       byte scanning, syntax, integer atoms, and include decoding
    layout.lisp, signatures.lisp
                       C layout and source function declarations
    scalar_syntax.lisp, scalar_types.lisp, scalar_resolve.lisp, pointer_types.lisp
                       source navigation, type equality, and symbol lookup
    hir_analyze_*.lisp integer, pointer, call, control, and lexical analysis
  ir/
    hir.lisp, hir_verify_*.lisp
                       typed HIR and structural, scope, and source checks
    integer_types.lisp integer width and representation rules
    ir_types.lisp, ir_verify_*.lisp
                       scalar operation contract and shared type checks
    ssa.lisp, ssa_lower*.lisp, ssa_verify*.lisp
                       typed CFG/SSA, PHI joins, and dominance verification
    lir.lisp, lir_lower.lisp, lir_verify*.lisp
                       virtual registers, edge copies, labels, and path checks
  backend/
    common.lisp        encoded function descriptors, independent of object format
    x86_expr.lisp, x86_memory.lisp, x86_control.lisp, x86_calls.lisp
    x86_stack.lisp
                       native x86-64 instruction and fixup encoders
    lir_emit_x86.lisp   verified flat LIR to x86-64 machine code
  object/
    elf64.lisp         first native cross-target ELF64 writer slice
    elf64_multi.lisp   native ELF64 symbol table for multiple functions
runtime/
  psl_runtime.h         versioned hosted value and root ABI
  gc.c                  mark-and-sweep collector
  startup.c             lazy hosted initialization
  platform_linux.c      Linux stack bounds
  platform_windows.c    Windows stack bounds
  value.c, cons.c, string.c, symbol.c, package.c, closure.c, values.c
                         separately selected dynamic facilities
```

`compile-source` coordinates reader → analyzer → verified HIR → CFG/SSA →
optional optimization → verified LIR → backend → object writer. The frontend
does not encode machine instructions. Each machine backend receives LIR and an
explicit target contract containing ABI registers, pointer width, stack
alignment, and object format. The ELF and COFF writers consume encoded
functions and relocations rather than source forms.
The FFI toolchain runs only when source explicitly declares a C translation
unit or the caller requests a linked artifact. Ordinary typed `-c` compilation
needs no C compiler. Hosted dynamic source records runtime module dependencies;
the linker compiles their transitive closure while typed programs select none.
The frontend computes C structure layout and passes the
supported aggregate ABI metadata to the backend. The object writer owns data
symbols and GOT relocations on Linux, while COFF uses relative relocations and
`.pdata`/`.xdata` unwind records. The selected system linker and archiver
produce Linux or Windows artifacts. Freestanding links use explicit startup
objects and linker scripts. Each backend encodes its own instructions;
compiler object generation has no assembler, LLVM, or third-party code-generation
library dependency.
The SSA representation has basic blocks, typed values, terminators, and `phi`
joins. The current language subset has conditional branches and a Boolean
`while` loop whose body may update raw storage.
LIR uses virtual registers and explicit labels after `phi` edge copies are
placed. See [the compiler pipeline](compiler.md) for stage APIs and invariants.

The source tree separates language analysis, portable IR, machine backends,
object formats, and external toolchain integration. Add a directory when it
contains real code, rather than creating empty placeholders for planned
targets or runtimes.

The first compiler components ported into compiled PSL are byte emission,
caller-owned arena allocation, scanning, syntax parsing, machine integer
atom parsing, C-compatible structure layout, and a first ELF64 writer slice.
The byte emitter is compared with
Stage 0 output. The scanner
records source spans; the parser builds an index-linked tree of lists and
prefix forms. These modules run at `-O0` and `-O1` on every hosted target.
`bootstrap/native-core.lisp` includes them in one compilation unit, preserving
ordinary PSL calls between components. `compile_scalar.lisp`, `x86_expr.lisp`,
and the small C file-I/O wrapper make a native executable that compiles
integer and pointer functions with independently typed parameters, literals,
nested binary wrapping
arithmetic, bit operations, lexical `let` and `progn`, comparisons, `if`, and
calls across the source file to an x86-64 ELF object. The native
multi-function writer separates local and exported ELF symbols and rejects
duplicate names. The native path analyzes source into word/Boolean HIR with
per-node integer type codes and pointer pointee references, verifies references,
arity, node shapes, lexical
scope, and source-type relationships, then lowers to verified typed SSA and
flat LIR before emitting x86-64 instructions.
Its restricted symbol handling accepts lowercase hyphenated Lisp names for
internal functions and locals, while C exports retain C-compatible names.
Call arguments form backward links in the portable type catalog. SSA lowers
argument expressions in source order. The baseline x86-64 LIR encoder saves
six incoming System V registers and stores each virtual register in its own
frame slot. Outgoing argument values are loaded after their expressions have
finished, so nested calls do not retain argument-evaluation pushes across
call sites. `x86_stack.lisp` owns outgoing stack area sizing, alignment,
adjustments, and slot stores. Arguments after the sixth are written to this
area before loading the six register arguments. Incoming stack parameters
are read at positive frame offsets.
`scalar_types.lisp` resolves declared source types and contextual literals.
`integer_types.lisp` supplies integer widths and representation checks. The
encoder extends narrow inputs, normalizes each result, and selects signed
comparison conditions from operand type codes. Explicit casts permit mixed
signatures and heterogeneous locals. Boolean literals and integer truth tests
preserve the `if` rule that integer zero is true. Test-and-body `cond` clauses
lower to typed conditionals; general macro expansion is still pending.
The native compiler directly compiles `integer_types.lisp`, `binary.lisp`,
`arena.lisp`, `atoms.lisp`, and `reader.lisp`; C checks compare their native output with
Stage 0 output and deterministic bootstrap builds. Memory analysis uses
source type equality and C layout metadata, and a separate verifier checks
loads, stores, pointer arithmetic, casts, field offsets, and Boolean loops
before encoding. These operations use the same runtime-free caller-owned
storage as the compiled modules.
The source pass records `defcstruct` layouts; a C harness compares size,
alignment, and field offsets against compiled C structures. Typed field
pointers can access nested structure fields; loads and stores support integers
and pointers. Structure values, floating accesses, and pointer qualifiers
remain outside the native function subset.
Native source inclusion is split between `frontend/source.lisp`, which
recognizes top-level include forms and decodes Lisp strings, and the temporary
`host/source.c` OS boundary, which reads files, resolves canonical paths,
checks active cycles, and splices forms into a shared source buffer. The
loader preserves include order and suppresses repeated canonical files.
The driver allocates signature and layout tables according to the source size;
it no longer has a 256-function ceiling. The ELF writer bounds counts by its
symbol/name field widths rather than that old development limit.

The native signature pass resolves grouped parameter declarations and return
types against those layouts before scalar body compilation. The scalar compiler
uses these records directly instead of parsing declarations again. It accepts the
headers and bodies of the complete native core. Dedicated component harnesses
compare byte emission, arena, integer parsing, scanning, syntax parsing, and
include decoding with Stage 0.
The driver first collects all signatures, then compiles bodies and patches
relative calls. This permits forward calls and recursion. It is a
restricted source-to-object proof, not Stage 1: general symbol interpretation,
macro expansion, full semantic analysis, generic optimization and effects,
general function calls,
relocations, data, and COFF still run in SBCL. The standalone native writer
also reproduces one-function AArch64 and RISC-V64 ELF objects from supplied
machine bytes.

Each major compiler module has its own Lisp package. `psl.compiler` is the public
library entry point and coordinates the pipeline. `psl` contains source-level
systems extensions. Source files get these names imported into a temporary
package, while standard Common Lisp symbols retain their normal meaning.

The native SSA verifier checks block termination, instruction ownership,
operand order, source types, call signatures, PHI predecessor coverage,
reachability, and definition dominance. Loop edges are explicit; lexical
bindings alias immutable SSA values. LIR lowering places PHI copies on incoming
edges and creates labels for branch edges. Its verifier reconstructs the CFG,
checks operation types and targets, and rejects register reads without a
definition on every incoming path. Shared scalar checks live under `ir/` and
use a type catalog rather than frontend trees. The x86-64 encoder reads LIR,
virtual-register types, symbols, and its own fixups; it does not read HIR or
SSA instructions. The earlier HIR-to-machine encoders have been removed.
Native generic optimization, effects, remaining ABI/backend features, and the
full Stage 1–3 comparison remain pending M8 work. The x86-64 Linux
`bootstrap_self_core.sh` gate now compiles the complete native core through
three native generations and runs the full native subset suite on each. The
core objects match byte for byte. Their C driver and source loader are shared
temporary host code, so this does not establish full self hosting.
