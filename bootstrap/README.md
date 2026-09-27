# Native bootstrap components

`native-core.lisp` is the growing PSL implementation of the compiler. It
includes separate source modules in one translation unit so their functions
use ordinary Lisp calls. Stage 0 builds the initial core. The resulting native
compiler can now compile every module included by `native-core.lisp`, including
its frontend, IR verifiers, x86-64 encoder, and ELF writer. A temporary C
adapter still supplies file I/O, canonical paths, and diagnostic rendering.
Allocation, initialization, cleanup, source traversal, argument validation,
compilation flow, and diagnostic selection live in PSL, with
explicit libc imports; this is
**not yet a complete Stage 1 compiler**.

From a fresh checkout on x86-64 Linux:

```sh
make
build/pslcc-native examples/basic/standalone.lisp build/standalone.o
./pslcc -c bootstrap/native-core.lisp -o /tmp/psl-native-core.o
sh tests/bootstrap_modules.sh
sh tests/bootstrap_binary.sh
sh tests/bootstrap_reader.sh
sh tests/bootstrap_parser.sh
sh tests/bootstrap_component.sh arena
sh tests/bootstrap_component.sh atoms
sh tests/bootstrap_elf64.sh
sh tests/bootstrap_native_compiler.sh
sh tests/bootstrap_self_core.sh
```

The native modules currently implement:

- Little-endian byte emission and 32-bit patching into caller-owned storage.
- Aligned allocation from a caller-owned arena.
- Token scanning with source byte spans, comments, strings, escaped atoms, and
  Lisp reader punctuation.
- List and prefix-form parsing into an index-linked, caller-owned node arena.
- Top-level `include` recognition and Lisp string decoding in
  `frontend/source.lisp`. `host/source_unit.lisp` owns relative path resolution,
  once-per-unit inclusion, active-cycle checks, and ordered source assembly.
  `host/source.c` provides file reads, canonical names, platform path policy,
  and error rendering. Missing files, malformed includes, and reader errors
  prevent object output.
- C-compatible structure layouts in caller-owned tables. The native source
  pass accepts `defcstruct`, computes field offsets, size, and alignment for
  the current 64-bit target slice, and resolves scalar, pointer, and earlier
  structure types. A C harness checks the layouts against compiled C structs.
- A typed signature pass for ordinary `defun` declarations. It records
  parameter and return shapes, grouped `type` clauses, and C exports before
  bodies are compiled. The scalar compiler consumes these same records, so
  declaration clause order and multiple function body forms work there.
  The pass accepts the declarations in the native byte emitter, arena, integer
  reader, and scanner modules. The byte emitter, arena, integer reader, and scanner bodies
  now compile through the native executable.
- Decimal and `#x`, `#o`, `#b`, and `#d` machine integer atoms with overflow
  detection.
- A first ELF64 writer for one exported x86-64, AArch64, or RISC-V64 function
  without data or relocations. Its output matches Stage 0 byte for byte for
  the accepted cases. A separate multi-function writer builds x86-64 symbol
  tables for several functions in source order. The x86-64 call writer emits
  undefined symbols and `R_X86_64_PLT32` relocations for referenced C imports;
  unused import declarations leave no object symbols.
- A restricted native compiler that accepts independently typed machine-integer
  parameters, locals, and results.
  Types are `u8`, `u16`, `u32`, `u64`, `s8`, `s16`, `s32`, `s64`,
  `usize`, `isize`, or `c-int` (an alias for `s32` in this slice).
  Raw `(ptr TYPE)` parameters, locals, and results also work, including
  nested pointer types and pointers to earlier C structures.
  It accepts range-checked literals, nested binary `wrap+`, `wrap-`, `wrap*`,
  and `bits-and` forms, `=` and typed `<` comparisons, explicit `wrap-cast`,
  and calls to functions defined anywhere in the same source file. Every call
  argument and result must match its declared source type; arithmetic operands
  must have equal types. `shr64` remains specific to `u64`.
  C calls use `(ffi:import-function "name" ((arg TYPE) ...) -> TYPE)` and
  `(ffi:call name ...)`. Imports currently accept lowercase C-compatible
  names and integer/pointer signatures, including `(ptr void)` and `void`
  results. Ordinary calls cannot invoke an
  import, and `ffi:call` cannot invoke an ordinary Lisp function. The native
  frontend checks duplicate names, parameter shapes, call arity, and source
  types before code generation. C harnesses verify narrow returns, pointers,
  `strlen`, integer-zero/null-pointer Lisp truth, register/stack calls and
  alignment, and static/shared consumption.
  `ffi:source`, data imports, floating/aggregate signatures, pointer
  qualifiers, and allocation-effect annotations still need native ports.
  It accepts `t`, `nil`, `if`, lexical `let`, `progn`, and test-and-body `cond`
  clauses. Integer zero is true in a condition; only Boolean `nil` is false.
  Test-only `cond` clauses remain unsupported. Binding initializers use
  parallel `let` scope, and local values occupy stack slots. Recursive calls
  work. Calls pass the first six integer or pointer arguments through the
  System V integer registers; further arguments use eight-byte stack slots.
  SSA evaluates arguments in source order and the LIR backend loads their
  saved values for calls, preserving stack alignment. C tests cover seven,
  eight, and nine parameters, signed narrow values and pointers on the stack,
  nested calls, recursion, and argument side effects.
  The encoder extends narrow parameters and normalizes wrapping results to
  the source width; signed comparisons use signed x86-64 conditions.
  Functions without `c-export` receive local ELF symbols.
  Source expressions become word/Boolean HIR nodes retaining an integer type
  code and pointer pointee references on each node. Structural, lexical-scope,
  and source-type verifiers run
  before SSA lowering. They check literal representations, operator types,
  parameter declarations, call signatures, cast operands, memory widths, field
  offsets, and pointer type relationships. The default native pipeline then
  builds verified typed SSA blocks and flat LIR. SSA has explicit PHI joins
  and loop backedges; LIR places PHI copies on predecessor edges. The LIR
  verifier checks labels and requires every register read to have a definition
  on all paths. The baseline x86-64 backend consumes LIR and its type catalog.
  `deref`, `store`, `pointer+`, `field-pointer`, `ptr-cast`, and
  `ptr-from-address` lower through separate memory analysis, verification, and
  encoding modules. Pointer arithmetic uses the element size and an `isize`
  offset; loads extend signed and unsigned integers correctly. Stores return
  their value and evaluate the address before the value. A Boolean `while`
  reevaluates its condition before each iteration and returns `nil`. Raw
  pointer zero remains true in `if`, as in the Stage 0 machine subset.
  Its x86-64 instruction encoder and ELF writers are in PSL;
  they invoke neither LLVM nor an assembler. The updated native slice runs
  on x86-64 Linux and Windows/Wine hosts and produces byte-identical objects.
  Stage 0 also cross-compiles the combined native unit to AArch64 and RISC-V64
  objects; the test script supports execution on those hosts when their cross
  compilers and runners are available. `driver.c` and `host/source.c` supply
  file I/O, canonical paths, and diagnostic rendering. The C main forwards
  argc/argv to the compiled PSL driver. Hosted memory and traversal are already compiled PSL modules.

`driver.lisp` now owns the compilation-unit pipeline, exposed as
`native_compile_unit(context, object, result)`. Callers supply freshly
initialized source, syntax/signature/layout tables, IR arenas, fixup arenas,
and output buffers. It returns one on success and zero on failure. The
`native_unit_result` record reports these failure phases:

| Phase | Failure | Location |
| --- | --- | --- |
| 1 | Layout declaration | One-based AST `form` |
| 2 | C import declaration | One-based AST `form` |
| 3 | Function declaration | One-based AST `form` |
| 4 | Reader, collection state, or empty unit | No location |
| 5 | Function predeclaration | Zero-based signature `index` |
| 6 | Function body pipeline | Zero-based signature `index` |
| 7 | Call patching | No location |
| 8 | ELF writing | No location |

Only the failing phase's location is valid. Arenas may contain partial work
after failure; the host writes the object file only after successful completion.
The PSL compiler driver maps these phases to source/function locations and
selects the exit status. The C adapter renders its selected message and provides
file/path services. The separately compiled PSL storage driver owns arenas.
An independent C API caller compiles a unit from memory, checks declaration,
reader, signature, body, and output-capacity failures, and links/runs the emitted
object with a forward Lisp call and a C import. It runs with each core generation.

This bootstrap compiler slice accepts lowercase Lisp names with digits, `_`,
and internal `-` characters. C exports use C-compatible lowercase names
(`a`–`z`, digits after the first character, and `_`); internal function
symbols may contain hyphens. The Stage 0 reader handles more
Common Lisp spelling rules; those rules have not yet been ported to the native
compiler.
Native `void` functions and calls execute effects without producing a machine
value. `progn`, `let`, `if`, and loop bodies can sequence void calls; a function
declared `(returns void)` must end in a void expression. Opaque `(ptr void)`
values can be passed, returned, stored as pointer fields, and explicitly cast
to or from typed pointers. Dereferencing or offsetting an opaque pointer is
rejected until it is cast to a sized pointee. Void parameters and fields are
rejected. Void is not `nil` and cannot be an `if` condition, arithmetic operand,
or ordinary machine-value argument. A C fixture exercises native `malloc`/`free`
imports, seven-argument void calls, forward calls, recursion, branches, loops,
opaque fields, and the true value of an opaque null pointer. SSA/LIR mutation
checks reject void values used as literals, PHIs, or return-register operands.

Its structure declarations use lowercase names and the primitive types handled
by `layout.lisp`. Field pointers support nested structures and quoted field
names. Structure values, float loads and stores, pointer
qualifiers, packages, and general macro expansion remain outside this native
slice. Include forms currently use the unqualified lowercase spelling.

The native frontend implements `(sizeof 'TYPE)`, `(alignof 'TYPE)`, and
`(offset-of 'STRUCT 'FIELD)` as `usize` literals from its layout table.
Quoted pointer designators such as `'(ptr void)` work; unsized `void`, unknown
types/fields, and malformed designators are rejected. `(ptr-address pointer)`
obtains a typed or opaque raw pointer's address as `usize` without a memory
read. To check allocation failure, use `(= (ptr-address memory) 0)`; the raw
pointer itself remains true in `if`. C harnesses compare layout queries with
`sizeof`, `_Alignof`, and `offsetof`, then check live/null pointers and
integer/pointer round trips across the full address width.
`sh tests/layout_queries.sh [TARGET]` runs the Stage 0 fixture at `-O0` and
`-O1` on each hosted target. Native core generations run the same C fixture,
reject malformed queries/address conversions, and compare deterministic objects.
The hosted driver uses these queries to allocate typed arrays and address checks
to detect allocation failure. `host/driver.lisp` compiles separately from the
core and exports `native_prepare_driver` and `native_release_driver`. Supply a
zeroed driver with an owned, free-compatible source; preparation allocates and
initializes arenas. On failure, release the partial storage; release is
idempotent and clears owning pointers. Release before preparing the driver
again. Its compilation context must not be used after release. `storage.lisp`
uses explicit `calloc`/`free` imports; the core retains no unresolved symbols.
The C harness compares allocations with C record sizes, checks context links
and capacity overflow, compiles from memory, releases/reuses a driver, and
injects failure at each of the 18 allocation points on Linux.

The native compiler now compiles its complete `native-core.lisp` translation
unit. Dedicated C harnesses also exercise native-generated integer rules, byte
emission, arena, integer reader, scanner, parser, and include decoding modules. Its C boundary checks match Stage 0, its object has no
unresolved symbols, and repeated builds and `-O0`/`-O1` bootstrap builds emit
identical objects. The integer module supplies width and representation rules
to the native analyzer and source-type verifier. The binary module checks
byte output and patch bounds; the arena checks alignment and capacity; the
scanner checks token spans, malformed input, and the example source corpus.
The Linux suite also compiles the byte emitter with no tool lookup path,
confirming that the native source-to-object path needs no external tools.
The integer reader checks radices, signs, token bounds, and overflow.

Calls within the native object are resolved to relative x86-64 displacements
after all function offsets are known;
the object has no unresolved symbols or linker relocations for these calls.

The component tests run `-O0` and `-O1`, compare byte emission with Stage 0,
and check deterministic objects. The native compiler test compares generated
objects from `-O0` and `-O1` bootstrap builds. The reader and parser tests
traverse the example source corpus on Linux. Pass a hosted target triple to the
component scripts to run
them under Wine or QEMU with the corresponding cross toolchain.
The native compiler test also checks that malformed HIR, SSA, and LIR are
rejected. Mutation cases cover wrong PHI predecessors, non-dominating uses,
invalid operand and label references, missing edge copies, and undefined
register reads. An ELF mutation harness rejects invalid relocation targets,
overlapping call positions, wrong opcodes/placeholders, contradictory import
reference flags, and malformed descriptor/arena metadata before writing bytes. The native modules are organized under `frontend/`, `ir/`,
`backend/`, and `object/`; the temporary C wrapper shares its ABI records with
the tests through `native_api.h`.

`sh tests/bootstrap_self_core.sh` bootstraps three successive native core
generations on x86-64 Linux. Each generation compiles `native-core.lisp` with
no external tool lookup path, then compiles the hosted storage, source loader,
and compiler driver modules and runs the same full native subset suite.
The native-generated core, hosted storage, source loader, compiler driver, and
fixture objects are byte-identical across generations, core objects have no unresolved symbols, and rejected-source
diagnostics match exactly. The same C host wrapper is linked to each core;
these are core generations, not complete Stage 1–3 compilers.

The source loader is compiled as its own PSL unit. It calls core parser/include
exports through their typed C ABI and explicitly imports string/memory and OS
services. `native_read_source_unit(path, length)` returns an owned NUL-terminated
buffer, including a valid empty buffer for an empty unit. Failed loads release
all partial state. The source-unit harness uses an independent in-memory OS
adapter to compare flattened bytes, include deduplication/cycles, reader errors,
POSIX/Windows path rules, and reuse after failure. On Linux it injects failure
at every malloc/calloc/realloc in both ordinary and empty loads and verifies
complete cleanup. The real OS adapter is exercised by the native compiler's
nested/repeated/symlink include fixtures on the supported hosts.

The compiler controller is also its own PSL unit. `native_run_compiler(source,
output)` returns 0 for success, 1 for rejected source, or 2 for usage/host/
allocation failure. `native_run_compiler_options(source, output, level)` selects
0 or 1; the default is 1. `native_compiler_main(argc, argv)` validates the
`[-O0|-O1] SOURCE.lisp OUTPUT.o` contract before reading argv. It owns state creation, source loading,
storage preparation, compilation, diagnostic phase/location selection, output,
and cleanup. C provides only the entry trampoline and primitive host adapters.
An independent provider fixture verifies all statuses, failure phase locations,
argument bounds, and cleanup, including failed state allocation on Linux. Real
process checks cover usage, unreadable input, rejected source, and an unwritable
output path. The previous C driver and the new PSL driver also produced identical
diagnostics for 58 rejected fixtures plus usage/I/O failures on Linux.

Native `-O1` folds constants in SSA: wrapping add/subtract/multiply, bitwise
AND, U64 shifts with counts modulo 64, signed/unsigned comparisons, integer
casts, equal integer/Boolean PHIs, and machine integer/pointer truth. Narrow
signed results retain their sign-extended word representation. PHI rewrites
preserve the verified prefix. The pass reaches a fixed point, updates the type
catalog, and verifies both its input and output. `-O0` skips optimization.
After folding, liveness starts from all block conditions/results and all calls,
loads, and stores, then follows their value dependencies, including argument
links and PHIs. Only live definitions and PHI edge copies reach LIR. Stable SSA
IDs and type records remain available for verification; a liveness verifier
rejects omitted roots/dependencies before lowering. Loads are retained
conservatively until native memory qualifiers and effects are ported. CFG
simplification and inlining remain open. The optimizer itself is compiled by every
native generation with no core runtime imports.

The optimizer fixture runs through Stage 0 and native `-O0`/`-O1`, compares C
observable results for width/signedness, large shift counts, equal joins,
zero/null truth with effectful imports, void calls, and loops, and checks that
the native `-O1` object is smaller. An argument-dependent unused expression
also has a smaller function symbol, demonstrating removal beyond folding;
discarded joins retain branch calls, and discarded store/load/void results
retain their effects. Both native modes also run the existing
stack-call, pointer/memory, mixed-integer, foreign-call, and void-call harnesses.
Repeat objects and generation snapshots are compared. IR mutation checks reject
malformed SSA at the optimizer's public entry point before rewriting it.
Liveness mutations reject missing calls, loads, stores, argument links, and
invalid flags; dead definitions have no LIR destinations, including dead PHIs.

The remaining bootstrap work is general symbol and string interpretation,
macro execution, the broader Stage 0 source/interop corpus, the remaining optimization passes
and effects, remaining target backends and object features, and the remaining
file/diagnostic/path adapter services. Full Stage 1–3 builds and their corpus comparisons remain
the M8 gate.
