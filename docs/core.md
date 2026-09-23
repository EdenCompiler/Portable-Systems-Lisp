# PSL Stage 0 implemented core

This file is the contract for behavior accepted by the current `pslcc`.
The [Core Specification](specification.md) defines M0 language semantics,
including facilities still awaiting implementation.

## Build and profiles

The Stage 0 compiler runs under SBCL. `pslcc -c source.lisp -o output.o`
produces an x86-64 ELF64 relocatable object. Accepted targets are
`x86_64-linux-gnu` and `x86_64-none-elf`; both currently use the System V AMD64
integer calling convention and ELF64 writer. `--profile=hosted|freestanding`
is accepted, but both flags currently compile the same typed subset. The
compiler does not yet link executables or provide a hosted Lisp runtime.
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
also accepts the older `psl:defun/c` spelling. `defstruct/packed` declares a layout-known packed
structure. Only C-compatible integer and raw-pointer arguments and returns
are implemented; at most six arguments can be passed in registers. Imported
and exported symbols use lower-case names for ordinary unescaped Lisp names.

Supported expressions are machine integer literals, `t`, `nil`, lexical
variables, `let`, `progn`, three-operand `if`, direct calls, `psl:wrap+`,
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

`(psl:ptr T)` is a raw pointer type, with optional `:const` and `:volatile`
qualifiers. `psl:pointer+` advances by elements; field access uses the
compile-time byte offset. Loads sign-extend signed narrow values and
zero-extend unsigned narrow values. Stores through `:const` pointers are
rejected. Raw dereferences require the caller to provide a valid, aligned,
live address. Stage 0 does not check bounds or lifetime at runtime.

`psl:defstruct/packed` lays fields out in source order with no padding and
alignment 1. Nested previously declared packed structures have known size.
The x86-64 backend supports unaligned packed-field accesses. C ABI structures
with natural alignment are not yet implemented.

## C source and function imports

C integration is marked at the source boundary:

```lisp
(ffi:source "ffi_math.c")
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
calls. The imported signature currently supports the same register-passed
integer and pointer types as exported functions. Source-file integration is
not yet available for the `none` target or other toolchains. FFI signatures
are trusted declarations; Stage 0 does not parse C headers to verify them.

## Object and runtime contract

The compiler emits ELF64 `ET_REL` for `EM_X86_64`, with `.text`, `.rela.text`,
`.symtab`, `.strtab`, `.shstrtab`, and a non-executable-stack note. Calls use
`R_X86_64_PLT32` relocations. Identical inputs, options, and compiler version
produce identical bytes when macros are deterministic. No libc, GC, tagged
object model, or PSL startup symbol is inserted into a typed object.

The `x86_64-none-elf` target produces an object, not a bootable image. The
hosted profile is not yet an ANSI Common Lisp implementation. Checked and
saturating arithmetic, native/C structure layout, static and arena storage,
certified allocation-free regions, dynamic objects, and other targets remain
on the [roadmap](roadmap.md).
