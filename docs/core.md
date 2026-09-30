# PSL Stage 0 implemented core

This file is the contract for behavior accepted by the current `pslcc`.
The [Core Specification](specification.md) defines M0 language semantics,
including facilities still awaiting implementation.

## Build and profiles

The Stage 0 compiler runs under SBCL. `pslcc -c source.lisp -o output.o`
produces a relocatable object. `x86_64-linux-gnu` and
`x86_64-none-elf` use System V AMD64 and ELF64; `x86_64-windows-gnu` uses
Microsoft x64 and COFF; `aarch64-linux-gnu` uses AAPCS64 and ELF64.
`riscv64-linux-gnu` and `riscv64-none-elf` use LP64D and ELF64.
`--profile=hosted|freestanding` selects
different source capabilities: both accept the typed machine subset, while
`hosted` additionally accepts managed values. The compiler links Linux
executables and libraries through GCC/binutils, and Windows `.exe`, `.a`, and
`.dll` through MinGW-w64. AArch64 and RISC-V64 Linux linking uses the selected
GNU cross linker. The two `none` targets can link static executables without
libc or PSL runtime objects, using `--startup`, `--entry`,
`--linker-script`, and `--map`. The `qemu-virt` startup uses QEMU's RISC-V
test device; `linux-exit` is an explicit Linux syscall shim for x86-64
user-mode emulation.
`-O0` skips optimization; the default `-O1` performs small-function inlining,
machine-width constant folding, and dead pure-value removal. Use
`--dump-ir=hir|ssa|lir|all` to inspect the verified pipeline.

A source file is read as UTF-8 into its own temporary Common Lisp package.
The compiler imports PSL names that do not conflict with Common Lisp into that
package, so source can use `u64`, `returns`, `wrap+`, and other extensions
without a `psl:` prefix. The qualified spellings remain valid. Common Lisp
`load` and `export` keep their meanings; pointer reads use `deref`, and C
exports use `c-export`.
Top-level `(include "relative-file.lisp")` splices another PSL source file into
the same compilation unit, resolving the path relative to the file that names
it. Repeated includes are read once; circular and missing includes are errors.
This lets native compiler components stay in separate source files while
sharing ordinary, unqualified PSL function calls. A nested `ffi:source` path
is resolved relative to its declaring file.
Top-level `defmacro` forms execute on the build host and become available to
later forms in the same source file. Source input is trusted build code; reader
macros and macro bodies may execute host Lisp. Target code is never executed
while cross compiling. The temporary package is discarded after compilation.

## Source forms

Ordinary `defun` is the preferred function syntax:

```lisp
(defun add (a b)
  (declare (type u64 a b)
           (returns u64)
           (c-export :c))
  (wrap+ a b))
```

Stage 0 requires simple parameter names, a leading `declare`, one machine type
for every parameter, and one `returns` declaration. `(c-export :c)` makes the
function visible to C; without it, the function is local to its object and
can still be called by other PSL functions in the same source file. The older
`psl:defun/c` spelling is also accepted. `defstruct/packed` declares a
layout-known packed structure. `defcstruct` declares a naturally aligned C
structure. C-compatible
integer, raw-pointer, `f32`, and `f64` scalar arguments and returns are
implemented, along with `void` results and `(ptr void)` for C `void*`.
On System V, integer and pointer arguments use up to six general registers,
floating arguments use up to eight SSE registers, and later arguments use the
stack. Naturally aligned C structs of one or two eightbytes containing integer,
pointer, `float`, or `double` fields can be passed and returned by value,
including mixed integer/SSE register classes and stack fallback. On Windows,
the first four parameter positions use `RCX`/`RDX`/`R8`/`R9` or the matching
`XMM0`–`XMM3`; callers reserve 32 bytes of shadow space. C structs of size
1, 2, 4, or 8 bytes pass directly, and other supported structs up to 16 bytes
pass by pointer with an indirect result. On AAPCS64, integer and pointer
arguments use `x0`–`x7`, floating arguments use `v0`–`v7`, and later
arguments use the stack. Supported C structs of at most 16 bytes use one or
two general registers, or floating registers for homogeneous float
aggregates of up to four members; the same rules apply to results.
On RISC-V LP64D, scalar arguments use `a0`–`a7` and `fa0`–`fa7`, then stack
locations. Supported small C structs use integer registers or the ABI's
floating-field rules, including one float plus one integer. A two-word
struct can split between the last integer register and the stack. Larger
aggregates, packed structures by value, variadic calls, and `long double` are
not implemented. Imported and exported symbols use lower-case names for
ordinary unescaped Lisp names.

Supported expressions are machine integer and floating literals, `t`, `nil`,
lexical variables, `let`, `progn`, three-operand `if`, direct calls, `psl:wrap+`,
`psl:wrap-`, `psl:wrap*`, `psl:bits-and`, `psl:shr64`, `psl:wrap-cast`,
`psl:while`, `=`, `<`, `psl:pointer+`, `deref`, `psl:store`,
`psl:ptr-cast`, `psl:ptr-from-address`, `psl:ptr-address`, and
`psl:field-pointer`. The compile-time
queries `psl:sizeof`, `psl:alignof`, and `psl:offset-of` accept quoted type or
field designators. `let` initializers see the outer lexical environment;
`if` treats only `nil` as false, so integer zero is true. Unsupported forms
produce a nonzero compiler exit and a diagnostic.

## Machine values and layout

Implemented integer types are `psl:u8`, `psl:u16`, `psl:u32`, `psl:u64`,
`psl:s8`, `psl:s16`, `psl:s32`, `psl:s64`, `psl:usize`, and `psl:isize`. Integer
literals are checked against the expected type when one is available.
Wrapping operators compute modulo the type's width; signed results use two's
complement. Comparisons produce internal Boolean values. Unqualified `cl:+`
retains its Common Lisp meaning and is not supported in Stage 0 compiled
expressions.
`bits-and` performs a bitwise AND on equal machine integer types. `shr64`
logically shifts a `u64` right by a `u64` count modulo 64. `wrap-cast` converts
between machine integer types by retaining the destination-width low bits,
then interpreting signed destinations as two's complement. `while` takes a
Boolean condition and one or more body forms; it checks the condition before
each iteration and returns false when the loop ends. These are PSL extensions,
not redefinitions of Common Lisp arithmetic or `loop`.

`f32` and `f64` correspond to C `float` and `double` in the implemented ABIs.
Floating literals, parameters, calls, and returns work; floating arithmetic
and comparisons are not implemented. C integer aliases follow the selected
ABI: `c-char`/`c-uchar`, `c-short`/`c-ushort`,
`c-int`/`c-uint`, `c-long`/`c-ulong`, `c-long-long`/`c-ulong-long`,
`c-size-t`, and `c-ptrdiff-t`. Windows uses LLP64, so `c-long` and `c-ulong`
are 32-bit there; they are 64-bit on Linux.

`(psl:ptr T)` is a raw pointer type, with optional `:const` and `:volatile`
qualifiers. `psl:pointer+` advances by elements; field access uses the
compile-time byte offset. Loads sign-extend signed narrow values and
zero-extend unsigned narrow values. Stores through `:const` pointers are
rejected. Raw dereferences require the caller to provide a valid, aligned,
live address. Stage 0 does not check bounds or lifetime at runtime.
`ptr-address` accepts one raw pointer and returns its address bits as `usize`.
It does not read the pointed-to storage. It is the explicit inverse of
`ptr-from-address`; zero addresses can be tested with ordinary integer `=`.
This does not change the rule that raw pointers, including null, are true in
Lisp conditions. Managed values and integers cannot be passed to `ptr-address`.

`psl:defstruct/packed` lays fields out in source order with no padding and
alignment 1. Nested previously declared packed structures have known size.
The x86-64 and AArch64 backends support unaligned packed-field accesses.
The RISC-V64 backend emits byte accesses for raw loads and stores, including
unaligned packed fields.
C ABI structures use each field's natural alignment and include trailing
padding. Nested structures are supported when declared first. `sizeof`, `alignof`, and
`offset-of` use the selected target's layout. The C layout tests compare
integer, floating, pointer, and nested fields with a C compiler.

## Hosted managed values

`--profile=hosted` accepts the opaque 64-bit `value` type. Integer literals
in a `value` position become signed fixnums; string literals become UTF-8
byte strings; `nil` and `t` have distinct
immediate representations. `cons`, `car`, `cdr`, `eq`, `make-symbol`,
`symbol-name`, and `package-name` operate on managed values. A managed `nil`
is false in `if`; every other managed value is true. The `psl` extensions
`box-fixnum`, `unbox-fixnum`, `make-byte-string`, `string-byte`,
`set-string-byte`, `make-package-from-name`, `intern-symbol`, and
`collect-garbage` expose the first runtime facilities. Managed values are
rejected in raw structure fields and raw pointer types because those locations
are not traced.

`#'(lambda (argument) ...)` captures visible `value` bindings and can be
called with `funcall`; this first closure convention accepts one argument
and returns one managed value. `(multiple-value-bind (a b) (values x y) ...)`
binds two managed values. The binding currently requires a direct `values`
expression. General lambda lists and full
Common Lisp multiple-value propagation are not implemented.

`without-allocation` checks all direct calls reachable from the region.
Unknown imported calls, managed allocation, explicit GC, and indirect closure
calls fail certification. An import may end with `:no-allocation` to declare a
trusted nonallocating effect. This promise is checked at compile time;
incorrect foreign annotations remain the caller's responsibility.

The runtime is a separately linked, single-threaded mark-and-sweep module set.
Only facilities used by hosted source and their dependencies are linked.
`pslcc -c` leaves runtime calls as undefined object symbols; linking a hosted
executable or library selects the required modules. The exact representation,
root interface, dependency edges, and current limitations are in the
[runtime contract](runtime.md). The hosted profile is still not ANSI Common
Lisp conforming.

## C source, function, and data imports

C integration is marked at the source boundary:

```lisp
(ffi:source "math.c")
(ffi:import-function "scale_c" ((value u64) (factor u64)) -> u64)

(defun scale_then_add (value)
  (declare (type u64 value) (returns u64) (c-export :c))
  (wrap+ (ffi:call scale_c value 2) 2))
```

`ffi:source` names a local `.c` file relative to the Lisp source file. For
Linux or Windows, `pslcc -c` compiles it with the selected C compiler and
combines it with the PSL object into one relocatable ELF64 or COFF object.
An `ffi:import-function` may also refer
to a C symbol supplied by a later link step, with no `ffi:source`. Imported
functions must be invoked with `ffi:call`; ordinary Lisp functions use normal
calls. The import string is the exact linker symbol. For a symbol whose case
cannot be written as an ordinary lowercase Lisp name, pass the same string to
the call, as in `(ffi:call "CreateFileA" ...)`. Data symbols use
`(ffi:import-data "name" type)` or
`(ffi:export-data "name" type initial-value)`. Use
`(ffi:address-of name)` to obtain a typed raw pointer, then `deref` or `store`
for integer, floating, or pointer data. Exported scalar data accepts a typed
literal initializer; pointer and structure data currently accept only zero
initialization. `(ffi:c-string "text")` creates private, NUL-terminated UTF-8
static bytes where a `(ptr u8)` argument or result is expected. It is an
explicit raw C pointer; ordinary string literals retain their hosted Lisp
meaning. The current bytes reside in writable static data and their pointer is
valid for the lifetime of the loaded object. The compiler
does not parse C headers to check declarations. Source-file integration is
not available for the `none` target. FFI signatures
are trusted declarations.

On x86-64 Linux or Windows, `pslcc source.lisp -o program` links an executable,
`--emit=static` writes a deterministic `.a`, and `--emit=shared` writes a
`.so` or `.dll`. Repeat `--link-input=FILE` for C objects or
libraries needed by the link. Static archive inputs must be object files:
`.o` on Linux, or `.o`/`.obj` on Windows.
Windows imports from another DLL use its MinGW import library as a link input;
the MinGW linker exports public PSL symbols from a generated DLL.
The `-c` path emits an object without invoking `cc` or `ar`, unless the source
explicitly contains `ffi:source`. Link outputs require Linux or Windows;
the `none` target remains object-only.

## Object and runtime contract

The Linux and `none` targets emit ELF64 `ET_REL` for `EM_X86_64`, with `.text`,
`.data`, `.rela.text`,
`.symtab`, `.strtab`, `.shstrtab`, and a non-executable-stack note. Calls use
`R_X86_64_PLT32` relocations. Data addresses use `R_X86_64_GOTPCREL` so they
work in shared objects and across preemptible symbols. Identical inputs,
options, and compiler version produce identical bytes when macros are
deterministic. A typed object has no implicit libc, GC, tagged-object, or PSL
startup symbol. Managed hosted objects reference only selected runtime modules.

The native bootstrap exposes data-only writers as `write_elf64_data` and
`write_coff64_data`. A `native_data_symbol` supplies an ASCII linker name,
caller-owned initialized bytes, power-of-two alignment up to 4096, and local or
global visibility. The complete declaration set is validated before output is
changed. The native source compiler also accepts `ffi:import-data` and
`ffi:export-data` declarations for integer and raw-pointer objects. Exported
integers use range-checked literal initializers; exported pointers require zero.
It lowers `ffi:address-of` through verified HIR, SSA, and LIR, then emits
initialized `.data`, object symbols, and PIC data relocations in the combined
code object. Native `ffi:c-string` literals use private byte definitions and
local object symbols on every implemented target. General named byte arrays,
read-only data sections, floating data, and aggregate initializers remain
pending.

Windows emits AMD64 COFF with `.text`, `.data`, `.pdata`, and `.xdata`, plus
`IMAGE_REL_AMD64_REL32` and `IMAGE_REL_AMD64_ADDR32NB` relocations. Its
`.pdata`/`.xdata` records describe the fixed function prologue for stack
unwinding. Windows linked outputs use a zero linker timestamp, and DLLs use a
stable image base for reproducible builds.

The `none` targets emit runtime-free objects and can link static images with
an explicit startup and linker script. The x86-64 `linux-exit` startup uses a
Linux syscall; the RISC-V `qemu-virt` startup runs on QEMU without an OS. The
hosted profile is not yet an ANSI Common Lisp implementation. Checked and
saturating arithmetic, general static and arena storage, and later targets
remain on the [roadmap](roadmap.md).

## Native bootstrap subset

The native executable built by `tests/bootstrap_native_compiler.sh` has a
separate, narrower source contract than Stage 0. It emits x86-64 SysV, AArch64 AAPCS64, or RISC-V64 LP64D ELF
objects for integer and raw pointer functions. The first six (x86-64) or eight
(AArch64/RISC-V64) arguments use integer registers; later arguments use eight-byte stack slots, with
padding after the final argument to preserve call alignment. Narrow values
are normalized on entry. Arguments are evaluated in source order before their
saved values are placed in ABI locations; nested and recursive calls work.
Pointers use unqualified `(ptr TYPE)` forms, with earlier C structures and
nested pointers as pointees. It supports `pointer+`, `deref`, `store`,
`field-pointer`, `ptr-cast`, `ptr-from-address`, and Boolean `while` in addition
to its integer, lexical, call, and conditional forms. Memory operations
preserve Stage 0's width, signed extension, evaluation order, and result rules.
Field designators may use `'field` or `(quote field)`. Pointee types remain
part of call, local, and result checking; integer zero cannot implicitly
become a pointer. Raw pointers, including address zero, are true in `if`.

Native C calls use `ffi:import-function` declarations and explicit `ffi:call`
expressions, with the same integer and raw pointer source types as ordinary
functions, including opaque `(ptr void)` arguments/results and `void` results.
Imported names are case-sensitive C-compatible strings. Lowercase imports use
the natural `(ffi:call name ...)` spelling; mixed-case imports use their exact
string spelling at the call site.
Declarations can appear before or after their callers. Duplicate names,
malformed parameters, mismatched arity/types, ordinary calls to imports, and
`ffi:call` on defined Lisp functions are rejected. Imported calls lower through
the same verified HIR/SSA/LIR pipeline. The ELF writer emits undefined function
symbols and `R_X86_64_PLT32` relocations only for referenced imports. Unused
imports are absent from the symbol table. C-built executables, static libraries,
and shared libraries consume these objects; the native CLI still emits objects
rather than invoking a linker.

Native C data declarations use `(ffi:import-data "name" type)`,
`(ffi:export-data "name" type initializer)`, and `(ffi:address-of name)`.
Integer and raw-pointer object types are supported;
the address expression has the corresponding pointer type and may be consumed
by `deref`, `store`, and the existing pointer operations. C names are
case-sensitive identifier strings, and an exact mixed-case string may be used
as the address designator. Exported integer literals are checked against their
declared width and signedness; exported pointer objects accept only zero.
Duplicate function/data names, malformed declarations, invalid initializers,
unknown objects, and address type mismatches are rejected. Only referenced
imports receive undefined symbols; every exported definition remains visible
to the linker. x86-64 ELF uses `R_X86_64_GOTPCREL`,
AArch64 uses the GOT page/low-12 pair, RISC-V uses
`R_RISCV_GOT_HI20` with a local `R_RISCV_PCREL_LO12_I` anchor, and COFF uses
`IMAGE_REL_AMD64_REL32`.

Native `void` calls may appear in sequences, `let` bindings/bodies, conditional
arms, and loop bodies. Functions declared `(returns void)` must end in a void
expression. Void results carry completion metadata through SSA/LIR; they never
become return-register values or PHI copies. Void parameters, structure fields,
conditions, arithmetic, and value arguments are rejected. Opaque pointers may
be passed, returned, stored in pointer fields, and explicitly cast. A `(ptr void)`
must be cast to a sized pointee before dereferencing or using `pointer+`.
Opaque null pointers are true under the raw-pointer Lisp truth rule.
Native `ptr-address` returns a `usize` from typed or opaque pointers; it is
checked through HIR/SSA/LIR. Native `sizeof`, `alignof`, and `offset-of` accept
quoted type/field designators and resolve to `usize` literals before lowering.
They use the same native C layout metadata as field access. Unknown types,
unknown fields, malformed/unquoted designators, unsized `void` queries, and
offset queries on nonstructures are rejected. These queries still cover only
the native subset's types and spelling rules.
Explicit libc imports such as `malloc` and `free` work; they do not become
implicit runtime dependencies of other units.

Native `ffi:source`, source strings/general byte data, floating/aggregate
signatures, and pointer qualifiers remain unsupported. Import effect annotations and
allocation-effect certification are implemented for the documented direct-call
subset; unannotated imports remain unknown.

`bootstrap/driver.lisp` exposes `native_compile_unit` for in-memory compilation
using freshly initialized caller-owned contexts and arenas. It collects layouts
and signatures, predeclares functions, compiles bodies through the verified
pipeline, patches calls, and writes the ELF object. Failures return zero with
a phase and AST/signature location in `native_unit_result`.
`bootstrap/host/driver.lisp` exposes `native_prepare_driver` and
`native_release_driver` for owned hosted storage. Preparation requires a zeroed
`native_driver` with a live, free-compatible source buffer, rejects wrapped
source/IR capacities, allocates zeroed arenas through explicit `calloc` imports,
and initializes every logical field. Failed preparation leaves partial storage
owned by the driver. Release frees partial/full storage and the source, clears
the owning pointers, and may be repeated; release before preparing again.
Compilation contexts become invalid on release. This hosted module explicitly
imports `calloc` and `free`; the native core remains free of unresolved symbols.
`bootstrap/host/compiler.lisp` exposes `native_run_compiler(source, output)`
and `native_compiler_main(argc, argv)`. It owns source loading, preparation,
unit compilation, output selection, and cleanup, and maps failing phases to
diagnostic locations. The native subset CLI takes `[-O0|-O1] [--target=TARGET] SOURCE.lisp OUTPUT.o`;
it does not yet accept Stage 0's other options. Supported native targets are
`x86_64-linux-gnu`, `x86_64-windows-gnu`, `aarch64-linux-gnu`, and
`riscv64-linux-gnu`. Status is 0 on
success, 1 for rejected language input, and 2 for usage, I/O, or allocation
failure. Arguments are inspected only for the expected count. Repeated run
calls allocate independent state and release it on every return. The temporary
C adapter writes objects and renders messages selected by the PSL driver.
`bootstrap/driver.c` is only a `main` trampoline.

Top-level lowercase `(include "relative-file.lisp")` now splices source into
the same unit. A native PSL parser identifies include forms and decodes their
filenames. The hosted PSL loader resolves relative include paths, deduplicates
canonical files, rejects active cycles, and assembles forms in source order.
Its PSL host units read files and canonicalize paths; a temporary C adapter
renders errors. Nested paths are relative to the file naming them. Reader and
include failures produce no
object. `native_read_source_unit` returns an owned, NUL-terminated byte buffer
and its length; the caller releases it with a free-compatible allocator. An
empty unit returns an owned empty buffer. Errors return null and release partial
frames, paths, syntax arrays, and assembled bytes. The loader is a separate PSL
translation unit using the core parser/include exports through their C ABI.

It does not yet support packages, general host macro execution, qualifiers,
floating accesses, or structure values. Its
implemented subset now passes verified HIR, typed CFG/SSA, and flat LIR; the
backend consumes virtual registers and explicit labels. Native `-O1` (the
default) now folds wrapping arithmetic, bitwise AND, masked U64 shifts, signed/
unsigned comparisons, integer casts, equal constant integer/Boolean joins,
and integer/raw-pointer truth through SSA. It normalizes narrow signed values
into the word representation and updates the type catalog with each rewrite.
SSA is verified before and after folding; LIR is verified before encoding.
Folding reaches a fixed point and preserves PHI prefix ordering. It retains
calls and memory operations on reachable paths. Boolean constant branches
become jumps; unreachable blocks/values are removed. Joins with one surviving
input become typed copies, including pointer/Boolean copies. Dense maps remap
operands, call links, block lists, terminators, and PHI predecessors in caller
storage; the type catalog is rebuilt and SSA is verified after compaction.
Folding and pruning iterate together until stable. A subsequent liveness pass omits
unused pure definitions and unused PHI copies from LIR. It keeps stable SSA
IDs/catalog records and verifies every retained dependency. Conditions,
returns, calls, stores, and all loads are roots; loads are conservatively
retained pending native memory qualifiers/effects. Native `-O0` skips both
passes and marks all definitions live.

Native `-O1` first inlines direct calls to verified one-block pure functions of
at most twelve SSA values. Parameters map to evaluated caller arguments;
unused arguments retain their observable effects. Constants, integer operations,
comparisons, casts, and copies are eligible; calls, memory operations, and CFG
joins exclude a callee. Typed copies replace calls, and SSA is verified after
insertion. The unit API collects templates before compiling bodies, including
forward callees. Templates use explicit caller-owned storage; a missing/full
cache or insufficient SSA capacity retains the original call. `-O0` skips
template collection and inlining. This is the bounded native subset port of
simple-function inlining; broader managed and ABI types remain pending.

Native `without-allocation` certifies direct calls before optimization. The
unit pipeline infers allocation-free summaries to a fixed point, including
forward calls and pure recursive groups. Unannotated C imports are unknown;
exactly one trailing `:no-allocation` declares a trusted promise. All region
calls, arguments, lexical initializers, loop bodies, and conditional arms are
checked, including dead arms. Outer lexical reads exclude earlier initializers.
Regions return their last typed body value, including void. Effect annotations
do not make calls pure for dead-value removal. Foreign promises remain the
caller's responsibility; managed/GC/indirect facilities are not native yet.
Use `native_compile_unit` for complete-unit summaries; `compile_scalar_form`
rejects region calls whose internal summaries are unfinished. Failure phase 9
identifies the caller index and unsafe callee name AST; diagnostics name the
call. HIR checks region metadata before certification and lowering.

`native_run_compiler_options(source, output, level)` selects 0 or 1; other levels
return a usage failure. In-memory callers set `context.optimization` to 0 or 1;
`native_prepare_driver` initializes it to 1. The exported optimizer rejects
invalid SSA before mutation. Managed/indirect effect support still needs a native
port. It directly compiles
its full native core, including frontend, IR verification, x86-64/AArch64/RISC-V64 encoding,
and ELF writing. Successive native core generations reproduce identical
objects and pass the native subset suite. The broader Stage 0 corpus, remaining
targets and ABI/object features, and the remaining C file/diagnostic/path adapter ports remain
open, so it is still an M8 development slice. See [the bootstrap contract](../bootstrap/README.md)
for its tests and remaining gate.

### Native output target selection

The native subset uses target IDs 0 (x86-64 Linux / SysV / ELF64, default) and
1 (AArch64 Linux / AAPCS64 / ELF64), and
2 (RISC-V64 Linux / LP64D / ELF64). `context.target` selects the output target;
`native_prepare_driver` initializes it to 0. An unsupported ID fails with phase
10 before source collection. `native_run_compiler_target(source, output, level,
target)` validates level and target before any source read or allocation.
The CLI accepts either supported `--target=...`, optionally together with
`-O0`/`-O1` in either order, before `SOURCE OUTPUT.o`.

All three output targets cover the current native integer/pointer/Boolean/void
subset with the same frontend and HIR/SSA/LIR verification. AArch64 uses eight
integer argument registers, 8-byte stack argument slots, aligned frames with
saved FP/LR, direct internal calls, and `R_AARCH64_CALL26` imports. The native
writer emits machine 183 and a local `$x` mapping symbol. Its existing ELF call
API defaults to x86-64; `write_elf64_calls_target` selects explicitly. Backend
and ELF validation reject unaligned AArch64 call/function spans and malformed
import placeholders. This does not add native floating-point, aggregate, data,
or general dynamic-language support.

Native RISC-V64 emits RV64IM instructions with LP64D ELF machine 243 and flag
4. Calls/jumps use fixed AUIPC/JALR pairs; imported calls use CALL_PLT (19),
zero addends, and no RELAX relocation. The writer rejects malformed pairs,
unaligned functions/fixups, overlapping call spans, and inconsistent imports.
Saved s0/ra and eight incoming argument registers occupy an aligned frame; s0
is the entry SP. Further arguments use eight-byte stack slots. C argument and
result boundaries sign-extend unsigned 32-bit values; internal values remain
zero-extended. Raw loads/stores use byte accesses for unaligned pointers.
Hosted native code/object buffers scale with source capacity and reject product
or additive overflow before allocation. The multi-function call writer accepts
text up to 2,147,481,592 bytes within caller-supplied storage, replacing its old
1 MiB development limit. Other standalone writer APIs retain their old limits.
