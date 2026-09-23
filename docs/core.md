# PSL Stage 0 implemented core

This file is the contract for behavior accepted by the current `pslcc`.
The [Core Specification](specification.md) defines M0 language semantics,
including facilities still awaiting implementation.

## Build and profiles

The Stage 0 compiler runs under SBCL. `pslcc -c source.lisp -o output.o`
produces an x86-64 ELF64 relocatable object. Accepted targets are
`x86_64-linux-gnu` and `x86_64-none-elf`; both currently use the System V AMD64
calling convention and ELF64 writer. `--profile=hosted|freestanding` selects
different source capabilities: both accept the typed machine subset, while
`hosted` additionally accepts managed values. The compiler links native Linux
executables, static archives, and shared libraries through `cc` or `ar`.
`-O0` skips optimization; the default `-O1` performs small-function inlining,
machine-width constant folding, and dead pure-value removal. Use
`--dump-ir=hir|ssa|lir|all` to inspect the verified pipeline.

A source file is read as UTF-8 into its own temporary Common Lisp package.
The compiler imports PSL names that do not conflict with Common Lisp into that
package, so source can use `u64`, `returns`, `wrap+`, and other extensions
without a `psl:` prefix. The qualified spellings remain valid. Common Lisp
`load` and `export` keep their meanings; pointer reads use `deref`, and C
exports use `c-export`.
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
for every parameter, one `returns` declaration, and `(c-export :c)`. It
also accepts the older `psl:defun/c` spelling. `defstruct/packed` declares a
layout-known packed structure. `defcstruct` declares a naturally aligned C
structure. C-compatible
integer, raw-pointer, `f32`, and `f64` scalar arguments and returns are
implemented, along with `void` results and `(ptr void)` for C `void*`.
Integer and pointer arguments use up to six general registers;
floating arguments use up to eight SSE registers. Further arguments use the
stack. Naturally aligned C structs of one or two eightbytes containing integer,
pointer, `float`, or `double` fields can be passed and returned by value,
including mixed integer/SSE register classes and stack fallback. Larger
aggregates, packed structures by value, variadic calls, and `long double` are
not implemented. Imported and exported symbols use lower-case names for
ordinary unescaped Lisp names.

Supported expressions are machine integer and floating literals, `t`, `nil`,
lexical variables, `let`, `progn`, three-operand `if`, direct calls, `psl:wrap+`,
`psl:wrap-`, `psl:wrap*`, `=`, `<`, `psl:pointer+`, `deref`, `psl:store`,
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

`f32` and `f64` correspond to C `float` and `double` in the current ABI.
Floating literals, parameters, calls, and returns work; floating arithmetic
and comparisons are not implemented. C integer aliases follow the selected
System V AMD64 LP64 ABI: `c-char`/`c-uchar`, `c-short`/`c-ushort`,
`c-int`/`c-uint`, `c-long`/`c-ulong`, `c-long-long`/`c-ulong-long`,
`c-size-t`, and `c-ptrdiff-t`.

`(psl:ptr T)` is a raw pointer type, with optional `:const` and `:volatile`
qualifiers. `psl:pointer+` advances by elements; field access uses the
compile-time byte offset. Loads sign-extend signed narrow values and
zero-extend unsigned narrow values. Stores through `:const` pointers are
rejected. Raw dereferences require the caller to provide a valid, aligned,
live address. Stage 0 does not check bounds or lifetime at runtime.

`psl:defstruct/packed` lays fields out in source order with no padding and
alignment 1. Nested previously declared packed structures have known size.
The x86-64 backend supports unaligned packed-field accesses. C ABI structures
use each field's natural alignment and include trailing padding. Nested
structures are supported when declared first. `sizeof`, `alignof`, and
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
`x86_64-linux-gnu`, `pslcc -c` compiles it with `cc` and combines it with the
PSL object into one relocatable object. The C output must be x86-64 ELF64.
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
not yet available for the `none` target or other toolchains. FFI signatures
are trusted declarations.

On x86-64 Linux, `pslcc source.lisp -o program` links an executable,
`--emit=static` writes a deterministic `.a`, and `--emit=shared` writes a
position-independent `.so`. Repeat `--link-input=FILE` for C objects or
libraries needed by the link. Static archive inputs must be object files.
The `-c` path emits an object without invoking `cc` or `ar`, unless the source
explicitly contains `ffi:source`. Link outputs currently require the native
`x86_64-linux-gnu` target.

## Object and runtime contract

The compiler emits ELF64 `ET_REL` for `EM_X86_64`, with `.text`, `.data`, `.rela.text`,
`.symtab`, `.strtab`, `.shstrtab`, and a non-executable-stack note. Calls use
`R_X86_64_PLT32` relocations. Data addresses use `R_X86_64_GOTPCREL` so they
work in shared objects and across preemptible symbols. Identical inputs,
options, and compiler version produce identical bytes when macros are
deterministic. A typed object has no implicit libc, GC, tagged-object, or PSL
startup symbol. Managed hosted objects reference only selected runtime modules.

The `x86_64-none-elf` target produces an object, not a bootable image. The
hosted profile is not yet an ANSI Common Lisp implementation. Checked and
saturating arithmetic, general static and arena storage,
other targets remain
on the [roadmap](roadmap.md).
