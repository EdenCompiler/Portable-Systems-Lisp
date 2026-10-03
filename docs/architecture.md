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
    identities.lisp     per-unit lexical and ordinary-call symbol identity
    runtime.lisp        hosted operations and module requests
    closures.lisp       lexical capture and closure functions
    strings.lisp        hosted UTF-8 source literals
    multiple-values.lisp  two-value source forms
    pointers.lisp        explicit raw pointer address conversion
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
  frontend/environment/  caller-owned build-host package/symbol tables and token decoding
  native-core.lisp      source unit including the ported compiler components
  driver_effects.lisp  unit fixed-point inference and allocation certification
  driver_inline.lisp   verified pure SSA template collection for a source unit
  target.lisp          native architecture/ABI/OS/object selectors
  binary.lisp          caller-owned byte emission and patching
  arena.lisp           caller-owned aligned allocation
  compile_scalar.lisp  native analysis, verification, and lowering coordinator
  driver.lisp          native compilation-unit pipeline and failure locations
  driver.c             main trampoline into the compiled PSL entry point
  unit_types.lisp      caller-owned compilation-unit result schema
  native_api.h         C host boundary for the compiled PSL modules
  *_types.lisp         shared record layouts, without compiler algorithms
  host/
    compiler.lisp      CLI argument validation and compilation flow
    compiler_diagnostics.lisp  failure phase and source-location selection
    compiler_types.lisp, compiler_imports.lisp  state and typed module/host ABI
    compiler.h        compiler diagnostic ABI constants
    diagnostics.lisp  compiler/source diagnostic wording and rendering
    platform_stdio.c  stderr and primitive host writes
    platform_toolchain.c  process adapter for explicit C-source compilation
    output.lisp         hosted object-file output through C file primitives
    driver.lisp         owned storage preparation and initialization coordinator
    driver_types.lisp   driver and storage record layouts
    storage.lisp        explicit calloc/free imports and partial cleanup
    output_capacity.lisp  checked output sizing from source-unit capacity
    initialize.lisp    per-record initialization of arenas and compilation context
    source_unit.lisp   include traversal, cycles, and source-unit assembly
    source_paths.lisp  relative/absolute include paths and platform path policy
    source_buffers.lisp  assembled bytes and canonical file ownership
    source_frames.lisp  per-file scanner/parser state and cleanup
    source_c_files.lisp  ordered canonical C-source ownership
    source_imports.lisp, source_types.lisp  typed host/core ABI and loader records
    source_io.lisp      hosted incremental file input through C stream primitives
    source_path_posix.lisp, source_path_windows.lisp
                       canonical file identity and host path policy
    source.h           source diagnostic ABI constants
  frontend/
    reader.lisp, parser.lisp, atoms.lisp, source.lisp
                       byte scanning, syntax, integer atoms, and include decoding
    data_types.lisp, data.lisp
                       imported C object records, declarations, and addresses
    layout.lisp, signatures.lisp, ffi.lisp
                       C layout, ordinary signatures, and explicit C imports
    layout_packed.lisp  packed-record registration through shared field validation
    integer_names.lisp  machine and ABI-dependent C integer source names
    float_bigint.lisp   caller-owned integer arithmetic for decimal conversion
    float_decimal.lisp  bounded decimal grammar and significand collection
    float_literals.lisp  IEEE payload rounding and conversion
    float_source.lisp  floating types, literal analysis, and scratch integration
    symbols.lisp, symbol_names.lisp
                       source spelling and canonical function names before encoding
    pointer_references.lisp  storage qualifiers on compiler pointee references
    scalar_syntax.lisp, scalar_types.lisp, scalar_resolve.lisp, pointer_types.lisp
                       source navigation, type equality, and symbol lookup
    hir_analyze_*.lisp integer, pointer, layout query, call, control, and lexical analysis
    effects_syntax.lisp region recognition and HIR source markers
    effects.lisp      direct-call allocation summaries and region traversal
  ir/
    hir.lisp, hir_verify_*.lisp
                       typed HIR and structural, scope, and source checks
    integer_types.lisp integer width and representation rules
    ir_types.lisp, ir_verify_*.lisp
                       scalar operation contract and shared type checks
    ssa_fold_scalar.lisp  target integer representation and constant arithmetic
    ssa_fold.lisp, ssa_optimize.lisp  SSA folding, catalog updates, and verification
    ssa_live.lisp      root/dependency marking and liveness verification
    ssa_branch.lisp    Boolean branch folding, reachability, and PHI repair
    ssa_remap.lisp     dense maps and surviving reference rewrites
    ssa_compact.lisp   arena record movement, catalog rebuild, and verification
    ssa_inline_templates.lisp  bounded pure callee snapshots and cache validation
    ssa_inline_insert.lisp  topological ID insertion and reference rewrites
    ssa_inline.lisp    argument substitution, clones, and typed call replacement
    ssa.lisp, ssa_lower*.lisp, ssa_verify*.lisp
                       typed CFG/SSA, PHI joins, and dominance verification
    lir.lisp, lir_lower.lisp, lir_verify*.lisp
                       virtual registers, edge copies, labels, and path checks
  backend/
    common.lisp        encoded function descriptors, independent of object format
    x86_expr.lisp, x86_memory.lisp, x86_control.lisp, x86_calls.lisp
    x86_stack.lisp
                       native x86-64 instruction and fixup encoders
    fixup_types.lisp, fixups.lisp  target-independent deferred call records
    aarch64_encode.lisp, aarch64_frame.lisp, aarch64_branches.lisp
                       instruction words, frame/argument locations, branch patching
    riscv64_encode.lisp, riscv64_frame.lisp, riscv64_memory.lisp,
    riscv64_branches.lisp  RV64IM words, LP64D frames, byte memory, paired branches
    lir_emit_x86.lisp, lir_emit_aarch64.lisp, lir_emit_riscv64.lisp
                       verified LIR machine encoding
    win64_frame.lisp, win64_probe.lisp, win64_arguments.lisp,
    lir_emit_win64.lisp  native Microsoft x64 frame and LIR encoding
    dispatch.lisp       explicit target/ABI selection for LIR and call patching
    scalar_abi.lisp     scalar GP/FP/stack location classes and signature queries
  object/
    elf64.lisp         first native cross-target ELF64 writer slice
    elf64_multi.lisp   native ELF64 symbol table for multiple functions
    elf64_calls.lisp   imported-call symbols and validated relocation output
    elf64_target_calls.lisp  PLT32/CALL26/CALL_PLT fields and AArch64 mapping symbols
    win64_unwind.lisp  native Microsoft x64 unwind-code encoding
    bytes.lisp, function_validation.lisp  shared object-byte and function checks
    data_types.lisp, data_validation.lisp, static_data.lisp
                       validated static data symbols and data-only ELF/COFF output
    elf64_data_imports.lisp, coff64_data_imports.lisp
                       combined code/data-import symbols and relocations
    coff64_layout.lisp, coff64_sections.lisp, coff64_symbols.lisp,
    coff64_relocations.lisp, coff64_validation.lisp, coff64_calls.lisp
                       native COFF section, symbol, relocation, and call writer
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
Its restricted symbol handling folds ordinary ASCII Lisp names, including
hyphenated exported names. Canonical source function names are copied into
caller storage when needed; explicit C strings and object API names remain exact.
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
The source pass records natural `defcstruct` and alignment-one
`defstruct/packed` layouts; a C harness compares size,
alignment, and field offsets against compiled C structures. Typed field
pointers can access nested structure fields; loads and stores support integer,
floating, and pointer values. Pointer qualifiers occupy reserved compiler-reference metadata
bits and are stripped before AST lookup; they never alter target addresses.
Type checks compare qualifiers, field pointers propagate them, and HIR/SSA/LIR
memory checks reject const stores. All loads remain optimizer effect roots.
The layout context carries the selected output target; `integer_names.lisp`
uses its ABI contract to resolve C long widths before layout and analysis.
Floating locals and memory operations use raw IEEE payloads in word slots;
HIR/SSA/LIR independently validate their width and type relationships. Decimal
conversion uses two caller-owned unsigned-word buffers and does not invoke a
host float parser. The hosted driver reserves reusable scratch in its data
arena; literal conversion does not advance its persistent data count.
Scalar ABI classification selects GP, FP, or stack locations per target.
Incoming FP payloads are saved only for functions with floating parameters,
and the LIR body keeps their raw bits in ordinary word slots. Structure values
remain outside the native function subset.
Native source inclusion uses `frontend/source.lisp` for `include` and
`ffi:source` recognition and Lisp string decoding. `host/source_unit.lisp` owns
traversal, active-cycle checks, and ordered assembly. Its path, buffer, and
frame helpers own relative
paths, canonical file records, syntax arrays, and partial cleanup. The separately
compiled loader imports the core's exported parser/include functions through
explicit typed C ABI declarations. The PSL `host/diagnostics.lisp` unit
selects and renders source errors. Its `platform_stdio.c` adapter only
exposes the host `stderr` stream and primitive byte/integer writes.
Separate PSL units read files, canonicalize names, and report platform path
policy. The PSL loader preserves Lisp form order, suppresses repeated canonical
include files, and returns an ordered canonical C-source list. Duplicate C
sources are errors. `platform_toolchain.c` is the conventional tool boundary:
it compiles only declared C files, performs a relocatable merge into a temporary
object, and atomically replaces the requested output after success. Machine
encoding and ELF/COFF writing remain in PSL.
The driver allocates signature and layout tables according to the source size;
it no longer has a 256-function ceiling. The ELF writer bounds counts by its
symbol/name field widths rather than that old development limit.

Native C imports share the signature/type tables with ordinary functions,
with a distinct imported flag. The frontend requires `ffi:call` at an imported
call site; ordinary Lisp calls remain unqualified. Signature string names are
validated as C identifiers and represented by atom slices in the syntax arena.
LIR call emission records referenced functions in their encoded descriptors.
Defined calls are patched directly; imported calls keep zero rel32 fields.
The ELF call writer independently verifies fixup targets, code bounds, opcodes,
placeholder bytes, nonoverlapping positions, and import reference flags. It
orders local and global symbols, omits unreferenced imports, and maps source
function IDs to ELF symbol indices for PLT32 relocations. Void results retain
separate source and broad HIR type codes. SSA void joins use a completion
marker with no value PHI; LIR emits neither edge copies nor return operands
for those results. The encoder skips result normalization/storage and return
loads for void, while preserving call arguments, stack restoration, and effects.
The type verifiers reject void machine-value consumers. Opaque pointee syntax
remains in pointer signatures and layout metadata; memory analysis requires a
sized pointee before accesses or pointer arithmetic. No assembler or
code-generation library participates in this path.

Imported and exported C objects have a separate typed declaration table and
fixup arena. The native frontend recognizes `ffi:import-data`,
`ffi:export-data`, and typed `ffi:address-of`; it rejects collisions with
function symbols and retains only referenced imports. Exported scalar
definitions retain initializer bits, size, and alignment. The shared IR carries
data addresses as a typed leaf. Explicit `ffi:c-string` expressions intern a
private NUL-terminated byte definition per source occurrence and use the same
typed data-address leaf. Repeated analysis passes reuse that definition.
Target encoders emit x86-64, AArch64, or RISC-V GOT address sequences, while
the COFF encoder emits a relative address sequence. The ELF and COFF object
modules validate instruction placeholders, local relocation anchors, symbol
indices, reference flags, initializers, layout, and fixup ordering before
writing combined code and initialized data sections.
ELF places private byte definitions with the local symbols before the first
global symbol; COFF marks them static. Both writers copy arbitrary initialized
bytes without routing them through an assembler.

`hir_analyze_layout.lisp` resolves native `sizeof`, `alignof`, and `offset-of`
to typed literals using the existing source layout table. Raw `ptr-address`
conversion has a distinct HIR operation and typed pointer-to-`usize` checks;
its lowering reuses ordinary conversion/move encoding. Stage 0 exposes the
same primitive through `frontend/pointers.lisp`, and its HIR/SSA/LIR verifiers
permit pointer-to-`usize` conversion while rejecting other integer result types.

The native signature pass resolves grouped parameter declarations and return
types against those layouts before scalar body compilation. The scalar compiler
uses these records directly instead of parsing declarations again. It accepts the
headers and bodies of the complete native core. Dedicated component harnesses
compare byte emission, arena, integer parsing, scanning, syntax parsing, and
include decoding with Stage 0.
The PSL unit driver first collects all signatures, then predeclares functions,
compiles bodies, patches relative calls, and invokes the selected object writer.
`native_compile_unit` exposes this pipeline on caller-owned source/arenas,
with a failure phase and AST/signature location. The separately compiled PSL
hosted driver allocates, initializes, and releases those arenas. Record layouts
are factored into declaration-only modules in their owning directories; the
hosted driver includes them without bringing in compiler algorithms. Its only
foreign imports are `calloc` and `free`; these stay out of `native-core.lisp`.
The PSL hosted compiler driver selects source/output handling, compilation
control, cleanup, and failure locations. Its entry point receives argc/argv
from a C `main` trampoline. A PSL input unit reads source files through imported
C stream primitives, and selected PSL path units canonicalize file identities
through POSIX or Windows host APIs. Temporary C adapters render the driver's
selected messages. A separate PSL output unit writes object files through
imported C file primitives. The adapters contain no compilation control or
phase/location selection.
This permits forward calls and recursion. It is a restricted source-to-object
proof, not Stage 1: general symbol interpretation, macro expansion, full
semantic analysis, managed values and indirect effects, aggregate
ABIs, general static byte data, and managed source string values still run in
SBCL or remain outside the native subset. Native ELF and COFF writers
handle the documented integer/pointer code, calls, unwind metadata, initialized
scalar data, and imported data relocations without an assembler.

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
The native optimizer now sits between SSA construction and LIR lowering. It
verifies its input, folds integer/Boolean values to a fixed point, updates the
shared type catalog, and verifies again. Pure arithmetic lives in
`ssa_fold_scalar.lisp`; representation rewrites live in `ssa_fold.lisp`; mode
selection/iteration/verification live in `ssa_optimize.lisp`. `ssa_branch.lisp`
folds Boolean branches and repairs joins against reachable predecessors.
`ssa_remap.lisp` rewrites references using dense value/block maps before
`ssa_compact.lisp` moves surviving records and rebuilds the type catalog.
Compaction uses existing arenas and per-record map fields, with no allocator
or host service. Structural SSA verification runs after compaction. Typed copy
kind 31 represents a join with one surviving input, distinct from LIR PHI edge
copy kind 104. Folding and pruning reach a joint fixed point. Calls/loads/stores
on reachable paths remain. `ssa_live.lisp` marks roots and their
dependencies, including PHIs and call argument links; LIR lowering omits
unmarked definitions/copies while retaining stable SSA IDs and type records.
A public liveness verifier checks structural SSA, root coverage, dependency
closure, and flag validity before lowering. Loads stay roots until native
memory qualifiers/effects are available. The driver accepts native `-O0`/`-O1` and
passes the chosen level through the compilation context. Context scratch fields
hold scan progress without adding a core allocator/runtime dependency.
Native allocation certification precedes SSA construction and optimization.
`frontend/effects_syntax.lisp` marks region roots without changing executable
HIR kinds. `frontend/effects.lisp` traverses region children and call signatures;
`driver_effects.lisp` computes a greatest fixed point in signature records
and validates all regions before emission. It rebuilds verified HIR in the
existing scratch arena, keeping function bodies and target encoding independent
of effect inference. Region markers have a metadata verifier. Signature flags
separate allocation-free candidates from finalized summaries; imported promises
are trusted explicitly. Error phase 9 selects the unsafe callee name, rendered
by the temporary host primitive. Optimizer call/load/store roots are unchanged.
`driver_inline.lisp` collects bounded, verified one-block SSA snapshots into
caller-owned storage before body compilation. `ir/ssa_inline.lisp` maps callee
parameters to evaluated caller arguments, clones only pure scalar instructions,
and replaces calls with typed copies. `ssa_inline_insert.lisp` shifts records
upward and rewrites value/list/terminator references while preserving block IDs.
Template validation runs before caller mutation; SSA verification follows
insertion, then folding and liveness run as before. Missing/full template
storage and insufficient caller capacity preserve valid calls. The hosted
storage unit owns/reclaims the extra cache; the native core has no new imports.
Managed/indirect effects, remaining ABI/backend features, and the
full Stage 1–3 comparison remain pending M8 work. The x86-64 Linux
`bootstrap_self_core.sh` gate now compiles the complete native core through
three native generations and runs the full native subset suite on each. The
core, hosted storage, source loader, input, path, compiler driver, output, and
diagnostic objects match byte for byte. A C harness compares
arena sizes and context links, injects failure at every allocation on Linux,
and checks overflow rejection, idempotent cleanup, and reuse. A separate mock
provider checks driver statuses, every diagnostic phase/location, valid/invalid
argument counts, state-allocation failure, and cleanup after all outcomes.
The C entry trampoline and primitive stdio adapter remain host code, so this
does not establish full self hosting.

The native output target is selected in the compilation context. Backend
`dispatch.lisp` chooses x86-64 SysV, Microsoft x64, AArch64 AAPCS64, or
RISC-V64 LP64D. The target contract keeps architecture, ABI, OS, and object
format separate. The frontend, optimizers, and IR verifiers are shared.
Deferred call arenas are target-independent. `elf64_target_calls.lisp` owns ELF
call fields and relocations; `coff64_calls.lisp` owns COFF calls and metadata.
Common object checks live in `function_validation.lisp`. CPU instruction
construction stays in `backend/`. The four current native output targets are
64-bit little-endian Linux ELF or Windows COFF. Broader ABI/data/runtime
ports remain pending.

The Stage 0 frontend's `identities.lisp` preserves host symbol identity during
analysis. Its per-unit maps produce deterministic lexical string keys for the
existing HIR/SSA interface, including fresh uninterned macro variables. The
ordinary-call map associates source symbols with signatures independently of
C linker names. `reader.lisp` distinguishes CL forms from exact PSL/FFI forms;
closures and multiple values use the same lexical mapping. These maps end at
analysis and introduce no target or object-format dependency.

The native frontend environment API owns copied symbol names, package aliases,
per-package presence and use tables, and symbol-token decoding. Its IDs are
independent of syntax-node references, target pointers, and object linker names.
The standard export catalogue is explicit PSL data and is checked against the
Stage 0 package exports; native initialization does not call SBCL. The
`bootstrap/frontend/environment.h` interface exposes caller-owned arenas for
component testing and reader integration. `resolve.lisp` assigns symbol IDs
and origin references in an arena parallel to syntax nodes before semantic
collection; `identity_syntax.lisp` gives analysis a common identity interface.
`index.lisp` accelerates presence lookup while preserving the independent
package enumeration chain. These modules belong to `native-core.lisp`.

The hosted driver owns environment storage and standard initialization through
`host/environment_storage.lisp` and `host/environment_initialize.lisp`.
Initialization calls the core seed API through an explicit C import; storage
uses declared allocator imports. The optional parser environment pointer keeps
standalone parser clients independent of hosted storage. C linker-name matching
remains separate from language symbol identity. Source-loader directives retain
their earlier spelling interface. Low-level visibility construction does not
implement language package transactions. `environment/operations.lisp` builds
single-symbol/package transactions over those primitives: it validates use and
export visibility before mutation, preserves symbol home identity, and removes
both presence chains together. The native core exports these APIs; arenas are
monotonic and stay caller-owned. Source package forms and macro evaluation still
require integration.
