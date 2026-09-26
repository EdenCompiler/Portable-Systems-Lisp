# Native bootstrap components

`native-core.lisp` is the growing PSL implementation of the compiler. It
includes separate source modules in one translation unit so their functions
use ordinary Lisp calls. Stage 0 builds the initial core. The resulting native
compiler can now compile every module included by `native-core.lisp`, including
its frontend, IR verifiers, x86-64 encoder, and ELF writer. A temporary C
host wrapper still supplies source traversal, file I/O, and memory; this is
**not yet a complete Stage 1 compiler**.

From a fresh checkout on x86-64 Linux:

```sh
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
  `frontend/source.lisp`. `host/source.c` supplies file reads, canonical paths,
  relative path resolution, once-per-unit inclusion, and cycle checks. Includes
  share an ordinary Lisp compilation unit; missing files, malformed includes,
  and reader errors prevent object output. This temporary host traversal still
  needs a PSL port.
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
  tables for several functions in source order.
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
  file I/O, source traversal, and memory until those facilities move into PSL.

This bootstrap compiler slice accepts lowercase Lisp names with digits, `_`,
and internal `-` characters. C exports use C-compatible lowercase names
(`a`–`z`, digits after the first character, and `_`); internal function
symbols may contain hyphens. The Stage 0 reader handles more
Common Lisp spelling rules; those rules have not yet been ported to the native
compiler.
Its structure declarations use lowercase names and the primitive types handled
by `layout.lisp`. Field pointers support nested structures and quoted field
names. Structure values, float loads and stores, `void` pointers, pointer
qualifiers, packages, and general macro expansion remain outside this native
slice. Include forms currently use the unqualified lowercase spelling.

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
register reads. The native modules are organized under `frontend/`, `ir/`,
`backend/`, and `object/`; the temporary C wrapper shares its ABI records with
the tests through `native_api.h`.

`sh tests/bootstrap_self_core.sh` bootstraps three successive native core
generations on x86-64 Linux. Each generation compiles `native-core.lisp` with
no external tool lookup path, then runs the same full native subset suite.
The native-generated core and fixture objects are byte-identical across
generations, core objects have no unresolved symbols, and rejected-source
diagnostics match exactly. The same C host wrapper is linked to each core;
these are core generations, not complete Stage 1–3 compilers.

The remaining bootstrap work is general symbol and string interpretation,
macro execution, the broader Stage 0 source/interop corpus, generic optimization
and effects, remaining target backends and object features, and a PSL driver
and source traversal. Full Stage 1–3 builds and their corpus comparisons remain
the M8 gate.
