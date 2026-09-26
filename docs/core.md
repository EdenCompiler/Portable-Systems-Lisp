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
`psl:ptr-cast`, `psl:ptr-from-address`, and `psl:field-pointer`. The compile-time
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
calls. Data symbols use `(ffi:import-data "name" type)` or
`(ffi:export-data "name" type initial-value)`. Use
`(ffi:address-of name)` to obtain a typed raw pointer, then `deref` or `store`
for integer, floating, or pointer data. Exported scalar data accepts a typed
literal initializer; pointer and structure data currently accept only zero
initialization. The compiler
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
separate, narrower source contract than Stage 0. It emits x86-64 SysV ELF
objects for integer and raw pointer functions. The first six arguments use
System V integer registers; later arguments use eight-byte stack slots, with
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

Top-level lowercase `(include "relative-file.lisp")` now splices source into
the same unit. A native PSL parser identifies include forms and decodes their
filenames; the temporary C host loader resolves canonical paths, reads files,
deduplicates repeated includes, and rejects active include cycles. Nested paths
are relative to the file naming them. Reader and include failures produce no
object. This host traversal still needs to move into PSL.

It does not yet support packages, general host macro execution, qualifiers, `void` pointers, floating accesses, or structure values. Its
implemented subset now passes verified HIR, typed CFG/SSA, and flat LIR; the
backend consumes virtual registers and explicit labels. Generic optimization
and allocation-effect analysis still need native ports. It directly compiles
its full native core, including frontend, IR verification, x86-64 encoding,
and ELF writing. Successive native core generations reproduce identical
objects and pass the native subset suite. The broader Stage 0 corpus, remaining
targets and ABI/object features, and C driver/source traversal ports remain
open, so it is still an M8 development slice. See [the bootstrap contract](../bootstrap/README.md)
for its tests and remaining gate.
