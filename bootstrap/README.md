# Native bootstrap components

`native-core.lisp` is the growing PSL implementation of the compiler. It
includes separate source modules in one translation unit so their functions
use ordinary Lisp calls. Stage 0 builds the initial core. The resulting native
compiler can now compile every module included by `native-core.lisp`, including
its frontend, IR verifiers, x86-64, AArch64, and RISC-V64 encoders, and ELF writer.
Allocation, initialization, cleanup, source traversal, argument validation,
compilation flow, and diagnostic rendering live in PSL, with
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
  `host/source_io.lisp` reads files through explicit hosted stream imports.
  The selected `host/source_path_*.lisp` unit obtains canonical names and host
  path policy from POSIX or Windows APIs. `host/diagnostics.lisp` renders source
  errors through the primitive stdio adapter.
  Missing files, malformed includes, and reader errors prevent object output.
- C-compatible structure layouts in caller-owned tables. The native source
  pass accepts `defcstruct` and `defstruct/packed`, computes field offsets, size, and alignment for
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
  tables for several functions in source order. The target call writers emit
  undefined symbols and target relocations for referenced C imports. Combined
  ELF and COFF writers also emit referenced imported-data symbols and PIC or
  relative data-address relocations. They lay out initialized exported scalar
  objects in `.data`; unused imports leave no object symbols, while exported
  definitions remain public even when Lisp code does not reference them.
- A restricted native compiler that accepts independently typed machine-integer
  parameters, locals, and results.
  Types are `u8`, `u16`, `u32`, `u64`, `s8`, `s16`, `s32`, `s64`,
  `usize`, `isize`, and the documented C integer aliases. The selected ABI
  supplies C long widths, including Windows LLP64.
  Raw `(ptr TYPE)` parameters, locals, and results also work, including
  nested pointer types and pointers to earlier C or packed structures.
  `:const` and `:volatile` qualifiers participate in type checking; const
  stores are rejected and field pointers retain their storage qualifiers.
  It accepts range-checked literals, nested binary `wrap+`, `wrap-`, `wrap*`,
  and `bits-and` forms, `=` and typed `<` comparisons, explicit `wrap-cast`,
  and calls to functions defined anywhere in the same source file. Every call
  argument and result must match its declared source type; arithmetic operands
  must have equal types. `shr64` remains specific to `u64`.
  C calls use `(ffi:import-function "name" ((arg TYPE) ...) -> TYPE)` and
  `(ffi:call name ...)`. Imports accept case-sensitive C-compatible names and
  integer/pointer signatures, including `(ptr void)` and `void`. A mixed-case
  linker name is repeated as a string at its call site. Ordinary calls cannot invoke an
  import, and `ffi:call` cannot invoke an ordinary Lisp function. The native
  frontend checks duplicate names, parameter shapes, call arity, and source
  types before code generation. C harnesses verify narrow returns, pointers,
  `strlen`, integer-zero/null-pointer Lisp truth, register/stack calls and
  alignment, and static/shared consumption.
  C data uses `(ffi:import-data "name" TYPE)`,
  `(ffi:export-data "name" TYPE INITIALIZER)`, and `(ffi:address-of name)`.
  Integer, floating, and raw-pointer objects flow through the same typed HIR/SSA/LIR
  pipeline. Exported integers accept range-checked literals; exported pointers
  accept zero. x86-64 ELF, AArch64 ELF, RISC-V ELF, and AMD64 COFF objects carry
  initialized data, symbols, and target relocation forms and link against the
  same C harness. The native loader collects `ffi:source` paths and the Linux
  host driver compiles and merges them for each hosted target. Data-only
  units emit empty-code objects without adding a function. Floating literals,
  locals, conditional joins, and pointer/field loads and stores preserve IEEE
  payloads, including signed zero, subnormals, and NaNs copied from C memory.
  Decimal conversion runs in PSL with caller-owned scratch. Scalar floating
  parameters, calls, and results use the selected C ABI. Aggregate signatures
  still need native ports;
  allocation-effect annotations use the
  native certification pass described below.
  It accepts `t`, `nil`, `if`, lexical `let`, `progn`, and test-and-body `cond`
  clauses. Integer zero is true in a condition; only Boolean `nil` is false.
  Test-only `cond` clauses remain unsupported. Binding initializers use
  parallel `let` scope, and local values occupy stack slots. Recursive calls
  work. Calls pass the first six integer or pointer arguments through the
  System V registers on x86-64, or the first eight through AAPCS64 registers
  on AArch64/RISC-V64; further arguments use eight-byte stack slots.
  SSA evaluates arguments in source order and the LIR backend loads their
  saved values for calls, preserving stack alignment. C tests cover seven,
  eight, and nine parameters, signed narrow values and pointers on the stack,
  nested calls, recursion, and argument side effects.
  The encoder extends narrow parameters and normalizes wrapping results to
  the source width; signed comparisons use signed x86-64 conditions.
  Functions without `c-export` receive local ELF symbols.
  Source expressions become word/Boolean HIR nodes retaining a scalar type
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
  Its x86-64/AArch64/RISC-V64 instruction encoders and ELF writers are in PSL;
  they invoke neither LLVM nor an assembler. The updated native slice runs
  on x86-64 Linux and Windows/Wine hosts and produces byte-identical objects.
  Stage 0 also cross-compiles the combined native unit to AArch64 and RISC-V64
  objects; the test script supports execution on those hosts when their cross
  compilers and runners are available. `driver.c` supplies the entry
  trampoline. `host/diagnostics.lisp` renders diagnostics through primitive
  writes from `host/platform_stdio.c`. The C main forwards argc/argv to the
  compiled PSL driver. Hosted memory and traversal are already compiled PSL modules.

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
| 8 | Target object writing | No location |

Only the failing phase's location is valid. Arenas may contain partial work
after failure; the host writes the object file only after successful completion.
The PSL compiler driver maps these phases to source/function locations and
selects the exit status. The C adapter renders its selected message and provides
diagnostic output. The separately compiled PSL storage driver owns arenas.
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

Its structure declarations use ordinary ASCII case folding and the primitive
types handled by `layout.lisp`. Field pointers support nested structures and
quoted field names, and retain pointer qualifiers. Structure values,
user packages, and general macro expansion remain outside
this native slice. Include forms use the implemented PSL source spelling.

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
uses explicit `calloc`/`free` imports and the core environment seed API; the
core retains no unresolved symbols.
The C harness compares allocations with C record sizes, checks context links
and capacity overflow, compiles from memory, releases/reuses a driver, and
injects failure at each of the 22 allocation points on Linux.

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
or AArch64 BL / RISC-V AUIPC+JALR immediates after all function offsets are known;
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
services. `native_read_source_unit(path, length, c_sources)` returns an owned
NUL-terminated buffer and an ordered list of canonical C sources, including a
valid empty buffer for an empty unit. A C source is resolved relative to the
Lisp file that declares it; duplicate canonical declarations are rejected.
Failed loads release all partial state. The source-unit harness uses an
independent in-memory OS adapter to compare flattened bytes,
include deduplication/cycles, reader errors,
POSIX/Windows path rules, and reuse after failure. On Linux it injects failure
at every malloc/calloc/realloc in ordinary, empty, and C-source loads and verifies
complete cleanup. The real OS adapter is exercised by the native compiler's
nested/repeated/symlink include fixtures on the supported hosts.

On an x86-64 Linux host, the native compiler passes collected C sources to a
small process adapter. It invokes the selected conventional C compiler without
a shell, merges the resulting objects with the PSL-owned object through `-r`,
and renames a complete temporary result into place. Deterministic linked tests
cover x86-64 Linux and Windows, AArch64 Linux, and RISC-V64 Linux. Generated
target-host compilers are not yet expected to launch this adapter.

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
catalog, and verifies both its input and output. Boolean constant branches
become jumps; a reachability pass removes unreachable blocks and their values.
Single-input PHIs become typed copies (integer, Boolean, or pointer). Dense
value/block maps rewrite operands, lists, terminators, predecessor IDs, and
argument links before moving records within the existing arenas. The type
catalog is rebuilt and SSA is verified after compaction. Folding and pruning
iterate together, so selected joins can expose further constant branches.
`-O0` skips optimization. After folding/pruning, liveness starts from all block conditions/results and all calls,
loads, and stores, then follows their value dependencies, including argument
links and PHIs. Only live definitions and PHI edge copies reach LIR. Stable SSA
IDs and type records remain available for verification; a liveness verifier
rejects omitted roots/dependencies before lowering. Loads are retained
conservatively until native memory qualifiers and memory effects are ported. Small
pure functions are inlined before folding. The optimizer itself is compiled by every
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
The CFG fixture compares Stage 0 and native behavior for constant true/false
branches, nested joins, Boolean/pointer copies, selected call effects, and
false loops. It compiles an infinite cycle without executing it, checks that
unreachable imports disappear from `-O1` objects, and compares repeat objects.
SSA mutations reject bad copy operands/types/predecessors and stale targets;
the cycle fixture verifies both an eliminated body and an eliminated exit.

Native `-O1` also inlines direct calls to verified one-block functions containing
at most twelve SSA values. Templates permit parameters, constants, wrapping
integer operations, comparisons, integer/pointer casts, and copies. Calls,
memory access, loops, and conditional joins exclude a callee. The unit driver
collects templates before compiling callers, so forward calls are eligible.
Clones map parameter uses to already-evaluated call arguments; repeated uses do
not repeat evaluation, and unused arguments retain their observable effects.
The call becomes a typed copy. Arena insertion preserves topological value IDs,
block instruction lists, PHI operands, and terminator references, then verifies
SSA before constant folding and liveness. Recursion is never expanded.

The hosted driver owns the template buffer plus imported-data and data-fixup
arenas, for twenty-one allocations in total, with partial cleanup covered by
fault injection. The core adds no
allocator or external runtime import. In-memory callers may omit the cache by
leaving its pointer and capacity zero. A full cache or full caller SSA arena
keeps calls intact. Cached template bounds, operand shapes, and parameter
positions are checked before rewriting a caller. C mutation tests reject invalid
templates without changing the SSA values and verify capacity fallback. The
interop fixture compares both optimization levels with Stage 0, including
signed widths, pointer identities, seven arguments, branches, loop bodies,
recursion, and unused effectful arguments. Object inspection confirms eligible
calls disappear and memory-reading calls remain. Native generations compare
the inliner and its generated fixture objects.

Native allocation certification runs before SSA optimization. The lowercase
`without-allocation` form returns its last body value, like `progn`, and may
return an integer, Boolean, pointer, or void. HIR retains region source markers;
metadata verification checks their parser references. Unit analysis computes
allocation summaries to a greatest fixed point: pure recursive groups remain
safe, and any function reaching an unannotated C import becomes unsafe. A C
import may end with exactly one `:no-allocation` annotation as a trusted promise.
This certifies allocation behavior; calls still remain optimizer effect roots.
The unit driver reuses scratch HIR storage while inferring summaries, then
checks all regions against finalized summaries before emitting any code.
Checks include call arguments, lexical initializers, loops, and both conditional
arms, including constant-dead arms. Reads of outer lexical bindings do not
recheck their earlier initializers. Standalone `compile_scalar_form` does not
trust unfinished internal summaries; use `native_compile_unit` to certify a
complete unit. Certification failures return phase 9, caller signature index,
and the unsafe callee's name AST reference in `result.form`; the CLI names the
uncertifiable call. Foreign annotation correctness is the caller's obligation.

C fixtures compare Stage 0/native behavior at both levels for forward calls,
pure mutual recursion, nested/void/pointer regions, outer lexical bindings,
loops, and retained foreign side effects. Rejections cover unknown/transitive/
recursive calls, dead arms, initializers, conditions, arguments, malformed
annotations, and empty regions. Unit API and diagnostic-provider fixtures check
failure phase/name selection and no output; metadata mutations reject invalid
region references. Native generations compare accepted objects and rejection
diagnostics. Managed allocation, GC, and indirect closures remain outside the
native source subset; their runtime/effect ports are still pending M8 work.

The remaining bootstrap work is general symbol and string interpretation,
macro execution, the broader Stage 0 source/interop corpus, optimization for broader types
and managed/indirect effects, remaining target backends and object features, and the remaining
file/diagnostic/path adapter services. Full Stage 1–3 builds and their corpus comparisons remain
the M8 gate.

## Native AArch64 output

The native compiler accepts `--target=x86_64-linux-gnu` (default),
`--target=x86_64-windows-gnu`, `--target=aarch64-linux-gnu`, and
`--target=riscv64-linux-gnu`. Either target option can precede or follow `-O0`
or `-O1`, before the source and output paths. Unknown targets and duplicate
options fail before reading source or allocating compiler storage.

```sh
make
build/pslcc-native --target=aarch64-linux-gnu tests/bootstrap_stack_arguments.lisp build/stack-aarch64.o
make test-native-aarch64
```

The AArch64 backend covers the same integer, pointer, Boolean, void, direct-call,
control-flow, and memory subset as the native x86-64 backend. AAPCS64 uses
x0–x7 for integer/pointer arguments and x0 for results; later arguments occupy
8-byte stack slots. Frames preserve x29/x30 and keep SP aligned to 16 bytes.
Narrow signed/unsigned parameters, results, and memory accesses preserve their
declared representation. The encoder uses caller-saved temporary registers,
without x18 or callee-saved x19–x28. Internal calls are patched directly;
imported BL instructions use ELF `R_AARCH64_CALL26` relocations with zero addends.
A local `$x` mapping symbol marks the text as AArch64 instructions.

`native_compile_context.target` selects native target ID 0 (x86-64 Linux) or
1 (AArch64 Linux). Preparation initializes it to 0. Unsupported IDs produce
`NATIVE_UNIT_TARGET` (phase 10) before source collection. Existing compiler and
ELF APIs retain their default target; `native_run_compiler_target` and
`write_elf64_calls_target` expose explicit selection. Architecture, ABI, OS,
and object-format selectors live in `target.lisp`; frontend and generic IR
passes are shared.

The output gate runs existing independent C harnesses under QEMU at both
optimization levels, compares behavior against Stage 0, inspects ELF/relocations,
links a shared library, and rebuilds all eight PSL compiler units across three
AArch64 native subset generations. It compares those units and fixture objects,
and confirms an AArch64 compiler host still produces identical x86-64 output.
The native core has no undefined runtime imports. Aggregate ABIs,
general packages/macros, and the complete
Stage 0 corpus remain open parts of M8.

`object/static_data.lisp` adds validated data-only ELF64 and COFF objects. Its
symbol records distinguish file-local and exported objects, preserve requested
power-of-two alignment, and carry caller-owned byte sequences without libc or
an assembler. Stage 0 and the native compiler build the writer independently;
tests compare the generated objects and link them to C on every hosted target.
Native imported and exported scalar data use the same symbol validation in
combined code objects. Source string literals and byte-array initializers
remain follow-up work.

Encoding and object contracts follow Arm's [AAPCS64](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst)
and [ELF for AArch64](https://github.com/ARM-software/abi-aa/blob/main/aaelf64/aaelf64.rst).

## Native RISC-V64 output

`--target=riscv64-linux-gnu` selects native target ID 2 (RISC-V64 / LP64D /
Linux / ELF64). Like the AArch64 target, it covers the documented native machine
integer, pointer, Boolean, void, direct-call, control-flow, and memory subset.
Integer-only functions emit RV64IM; floating signatures also use F/D payload
moves. ELF flags declare the LP64D link ABI (flag 4), without compressed
instructions. Aggregate source signatures remain unsupported.

The encoder uses fa0–fa7 for floating arguments and fa0 for floating results,
a0–a7 for integer arguments and a0 for integer results. Exhausted FP arguments
use available GP registers before stack slots. It preserves s0/ra,
keeps SP sixteen-byte aligned, and leaves gp/tp untouched. s0 points at the
entry SP; the saved frame pointer and return address lie at s0-16/-8.
Narrow inputs/results are normalized internally. Unsigned 32-bit values are
sign-extended at argument/result ABI boundaries as required by the psABI,
while ordinary PSL arithmetic and casts retain their unsigned representation.
Raw pointer operations use byte-wise memory access to support unaligned data.

Calls and label jumps use fixed AUIPC/JALR pairs. Internal pairs are patched
with signed PC-relative offsets; imported calls use `R_RISCV_CALL_PLT`, zero
addends, and zero immediate placeholders. The writer validates both words,
registers, alignment, spans, import references, and nonoverlapping fixups.
No `R_RISCV_RELAX` relocations are emitted, so linker code deletion cannot
invalidate already patched internal distances. Text is bounded by the paired
instruction reach (2,147,481,592 bytes), while caller-owned buffer capacity
still controls actual emission. The separate standalone ELF writer APIs retain
their earlier bounds.

Hosted driver output buffers now scale from source-unit capacity: the code
buffer reserves 1 MiB plus 16 bytes per source byte/node capacity, and the
object buffer adds 64 bytes per capacity plus 1 KiB for ELF overhead. Products
and additions are checked before allocation. Allocation failures and exhaustion
produce compilation failure and release all storage; this is bounded storage,
not a promise to accept arbitrary source size. Existing twenty-two-allocation
fault/cleanup checks cover the larger buffers and boundary overflow cases.

```sh
make
build/pslcc-native --target=riscv64-linux-gnu tests/bootstrap_stack_arguments.lisp build/stack-riscv64.o
make test-native-riscv64
```

`tests/bootstrap_native_elf.sh` owns the shared AArch64/RISC-V native output
gate; the target scripts select toolchains/runners. It checks O0/O1 C behavior
against Stage 0, deterministic ELF objects, static/shared library calls, and
three native subset generations of all eight PSL compiler units under QEMU.
RISC-V-specific C boundary checks inspect raw unsigned-32 register/stack/return
bits and unaligned memory, and generation outputs reproduce those fixtures.
The ABI follows the [RISC-V psABI](https://riscv-non-isa.github.io/riscv-elf-psabi-doc/).

## Native Windows output

`--target=x86_64-windows-gnu` selects native target ID 3 (x86-64 / Microsoft
x64 / Windows / COFF). The shared verified HIR, SSA, and LIR feed a Win64 body
encoder. Its frame keeps RSP sixteen-byte aligned and stationary after the
prologue, reserves outgoing shadow and stack arguments, and saves incoming
registers and virtual values. Large frames probe stack pages without a runtime
import. Functions carry frame and prologue metadata for the native `.pdata`
and `.xdata` writer.

The compiler COFF writer emits `.text`, `.data`, `.pdata`, `.xdata`, local/exported
functions, referenced imports, `IMAGE_REL_AMD64_REL32` calls, and
`IMAGE_REL_AMD64_ADDR32NB` unwind references. Its writer API validates function
spans, symbol names, call fields, import references, and encoded prologues
before touching output. Relocation counts above 65,535 use the COFF extended
count record. No LLVM, assembler, or third-party object library participates.
The same code object can contain undefined imported-data symbols, initialized
exported scalar objects, and `IMAGE_REL_AMD64_REL32` address relocations. The
separate static-data writer additionally supports caller-owned byte sequences
and local symbols.

```sh
make
build/pslcc-native --target=x86_64-windows-gnu tests/bootstrap_answer.lisp build/answer-win.o
make test-native-windows
```

The Windows gate runs independent C harnesses at `-O0` and `-O1`, compares
behavior with Stage 0 under Wine, inspects COFF relocations and unwind data,
links static and shared libraries, checks negative writer mutations and
extended relocation counts, and reproduces all eight compiler modules across
three Windows native subset generations. `make test-native-win64-frame` checks
large-frame probes and virtual unwinding at partial prologues.

M8 remains open: general source packages/macros, broader managed/runtime and
ABI/data ports, and full Stage 1–3
source/object/interop corpus comparisons are still required.

## Hosted object output

`host/output.lisp` is a separately compiled PSL unit. The compiler driver calls
its exported `native_host_write_object`; the unit imports `fopen`, `fwrite`,
`fclose`, `calloc`, and `free` from the host C library. It creates the binary
mode string in owned storage, writes the exact object bytes, closes the stream,
and returns failures to the PSL driver. This hosted service is separate from
machine instruction encoding and does not affect freestanding output.
`host/diagnostics.lisp` renders compiler and source diagnostics. Its small
`host/platform_stdio.c` adapter only exposes stderr and primitive writes.

## Hosted source input

`host/source_io.lisp` owns opening and incrementally reading source files. It
uses `fopen`, `fread`, `feof`, `ferror`, and `fclose` through explicit FFI
imports, grows owned storage with checked arithmetic, appends the parser's NUL
sentinel, and releases every partial allocation on failure. The independent
input harness covers empty, binary, 4095-byte boundary, and multi-buffer files,
missing paths, and each allocation failure on Linux. All native generation
gates compile and compare this PSL unit.

## Hosted canonical paths

`host/source_path_posix.lisp` imports `realpath`; the Windows unit imports
`_fullpath` plus handle-based final-path APIs so aliases share one source-unit
identity. Both export the same canonicalization and path-policy interface to the
loader. A cross-host harness checks lexical aliases, missing files, and platform
policy. Exact mixed-case Windows imports also exercise the native frontend's
case-sensitive C symbol handling. All generation gates compile and compare the
selected seventh PSL unit.

The native core also exports a build-host package/symbol reader component in
`frontend/environment/`. It uses caller-owned arenas and one-based symbol IDs,
seeds the actual CL/PSL/FFI export catalogue, and decodes ASCII symbol tokens
with case, escapes, qualification, keywords, and fresh `#:` identities. Run
`make test-native-environment` for catalogue, SBCL reader-oracle, visibility,
and bounds checks. The hosted driver attaches identities before semantic
collection. `tests/bootstrap_reader_identity.sh` checks qualified/escaped
operators, types, declarations, ordinary calls and lexical references against
Stage 0 linked C behavior at O0/O1, plus native rejection of distinct symbols.
Indexed lookup is checked with all names in one bucket and with 1,024 buckets.
General source packages and macros remain pending.

The same environment interface now provides single-symbol import/export,
shadowing and unintern operations, plus single-package use/unuse. Run
`tests/bootstrap_package_operations.sh [COMPILER] [TARGET]` for independent SBCL
observations and C visibility/ownership checks with fallback, collision-only,
and normal indexes. Removed records retain their arena consumption. Source
package forms, list transactions and macro evaluation remain pending.
