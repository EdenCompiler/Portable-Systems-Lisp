# Portable Systems Lisp Core Specification

**Revision:** 1.0 M0 baseline

**Scope:** source language, compile-time behavior, machine model, and execution
profiles. This specification defines intended semantics. The separate
[implemented core](core.md) states what the Stage 0 compiler accepts today.
Features marked **specified, not implemented** remain conformance targets and
must produce a compilation error until implemented.

The normative words **must**, **must not**, and **may** express requirements.
A program is *well formed* only when it satisfies the rules of its selected
profile and target. Where this document leaves behavior implementation-defined,
the implementation must document the selected behavior for that target.

## 1. Source, reader, and names

1. Source is a sequence of Common Lisp S-expressions. The hosted profile aims
   to accept the ANSI Common Lisp reader syntax and preserve its meaning. The
   freestanding profile uses the same token and list syntax, but need not make
   every readable object available at runtime. Unsupported reader syntax must
   be diagnosed; it must not silently change meaning.
2. Symbols have Common Lisp package identity. `cl:` forms retain Common Lisp
   semantics. PSL extensions are exported from the `psl` package. Nonconflicting
   extension names are imported into each source unit, so their unqualified
   names are available. Names conflicting with Common Lisp remain qualified;
   `deref` and `c-export` provide unqualified pointer and C-export spelling.
   The `psl:` spelling remains available when qualification is useful. A package and a
   compilation module are distinct: packages name symbols; modules own source,
   imports, exports, and link dependencies.
3. Compilation processes top-level forms in source order. A macro definition
   becomes available to subsequent forms. Macro expansion is complete before
   target code generation. Reader evaluation and macros are trusted build code
   and execute on the build host, never on the target.
4. `quote` returns source-level constants in hosted code. In freestanding code,
   quoted constants are permitted only if they can be represented without an
   unavailable runtime facility. A quoted symbol or list must be rejected when
   no symbol/list runtime is selected. **Specified, not implemented** in Stage 0.
5. The source encoding is UTF-8. Portable exported C symbol names are ASCII
   unless the target ABI and object writer explicitly document another encoding.
   The Stage 0 reader uses SBCL's reader and currently requires trusted input.
   Core source uses parentheses for lists, semicolon line comments, `#|...|#`
   block comments, Common Lisp symbol/package spelling, integer radix syntax,
   strings, and quote abbreviation. Reading a form does not imply that the
   current compiler can lower it to machine code.

## 2. Evaluation and profiles

The **hosted** profile preserves Common Lisp evaluation rules for standard
forms: lexical variables, left-to-right argument evaluation, `let` parallel
initializers, `let*` sequential initializers, `progn` order, and `if` truth
rules. Only `nil` is false; integer zero is true. Dynamic bindings, conditions,
CLOS, general `eval`, and the full numeric tower require later runtime work.
The hosted profile is not ANSI conforming until M9 is verified.

The **freestanding** profile guarantees, once implemented, function calls,
lexical variables, conditionals, local bindings, macros, fixed-width machine
integers, raw pointers, layout-controlled structures, static storage, and
explicit memory operations. It assumes no OS, libc, GC, streams, or dynamic
loader. A freestanding program may opt into additional runtime modules; using
an unavailable capability is a compile-time error. Profile selection is
explicit via `--profile=hosted|freestanding`; a source file must not silently
switch profiles. The target selection is independent of the profile.

The Stage 0 compiler accepts only the subset listed in [core.md](core.md). It
currently accepts the same typed forms under both profile flags. This shared
subset does not imply that the hosted runtime exists.

## 3. Machine types and literals

The required integer types are `psl:u8`, `psl:u16`, `psl:u32`, `psl:u64`,
`psl:s8`, `psl:s16`, `psl:s32`, `psl:s64`, `psl:usize`, and `psl:isize`. `uN`
contains integers from 0 through 2^N−1. `sN` contains integers from −2^(N−1)
through 2^(N−1)−1. `usize` and `isize` have the target pointer width; the
currently supported machine targets use 64 bits. Width and signedness are
semantic types, not merely optimizer hints.

An unannotated integer literal is an exact compile-time integer. When an
expected machine type exists, the compiler checks that the literal fits that
type and then gives it that type. If no expected type exists, a typed context or
explicit conversion is required before machine code emission. An out-of-range
literal is a compile-time error; it does not wrap implicitly. In the current
typed subset, a literal without an expected type defaults to `u64` when
nonnegative and `s64` when negative; broader exact-integer expressions are
deferred to hosted runtime work.

Common Lisp `cl:+`, `cl:-`, and `cl:*` retain exact arithmetic semantics in
hosted code. Machine operations are explicit `psl:wrap+`, `psl:wrap-`,
`psl:wrap*`, `psl:checked+`, `psl:checked-`, `psl:checked*`,
`psl:saturating+`, `psl:saturating-`, and `psl:saturating*`. The operands and
result have the same machine integer type. Wrapping operations compute modulo
2^N; signed results reinterpret the N-bit pattern as two's complement. Checked
operations signal an arithmetic condition in hosted code or execute a target
trap in freestanding code on overflow. Saturating operations clamp to the
minimum or maximum of the result type. Comparison returns a Boolean with
Common Lisp truth behavior. A conversion between machine integer types must
be explicit and must name its overflow policy. **Checked, saturating, and
conversion operations are specified, not implemented.**

## 4. Raw pointers and memory

`(psl:ptr T)` denotes a raw pointer to `T`; optional `:const` and `:volatile`
qualifiers restrict stores and memory optimization respectively. Raw pointers
are separate from managed Lisp object references. A null pointer has the
all-zero address representation on supported targets. Pointer width, alignment,
and address spaces come from the selected target.

`psl:address-of` obtains a pointer to addressable storage. `psl:pointer+`
advances by a signed element count multiplied by `sizeof(T)`; it may form a
one-past pointer, which must not be dereferenced. `psl:load` and `psl:store`
access the pointed-to value and obey its type, alignment, and qualifiers.
`deref` is the unqualified spelling of `psl:load` in source units.
`psl:ptr-cast` changes the pointer type without changing address bits;
`psl:ptr-from-address` explicitly converts an integer address to a pointer;
`psl:bitcast` reinterprets equal-sized machine values. `psl:store` returns the
stored value. Integer-to-pointer
conversion is never implicit. Volatile loads and stores are observable and
must not be removed or combined by optimization; volatile does not imply
atomicity.

The programmer is responsible for valid addresses, lifetime, and alignment at
raw-memory boundaries. Dereferencing null, invalid, expired, or misaligned
pointers has undefined behavior; the compiler may diagnose cases it can prove.
Pointer arithmetic does not itself read memory. Memory-mapped device access
uses explicit volatile pointers. **Raw pointer loads/stores, casts, element
arithmetic, and field pointers are implemented in Stage 0. `address-of` and
general `bitcast` are specified, not implemented.**

## 5. Structures and layout

`psl:defstruct/packed` declares fields in source order with no inter-field or
trailing padding and alignment 1 unless an explicit larger alignment is
requested. `psl:defcstruct` uses the selected target's C ABI size, alignment,
and field-offset rules. Fields have fixed machine types or other layout-known
structures; a dynamic Lisp object is not allowed in a freestanding layout
without an explicit representation.

`psl:sizeof`, `psl:alignof`, and `psl:offset-of` are target-dependent
compile-time queries. A field pointer is computed from the structure pointer
and its constant field offset. Structure layout does not change byte order;
portable wire formats must use explicit endian conversion. Packed fields may be
unaligned, so generated accesses must tolerate the target's rules or lower to
safe byte operations. **Basic packed structures and naturally aligned C
structures are implemented for x86-64, AArch64, and RISC-V64. By-value C calls
currently support small scalar-field structures according to each target ABI,
including mixed integer and SSE register classes on System V AMD64 and
floating-field rules on AArch64 and RISC-V64; larger and packed aggregate cases
remain outside the implemented subset.**

## 6. Storage and allocation effects

Stack storage has lexical lifetime; static storage lasts for the linked image;
arena storage lasts until its arena is reset or destroyed. Raw allocation
requires an explicitly supplied allocator. Managed allocation requires a linked
runtime module. A pointer to stack or arena storage must not be used after that
storage expires. GC is optional for typed programs and cannot be introduced by
an unrelated compiler feature.

`psl:without-allocation` certifies that a region and all transitively called
code perform no dynamic storage allocation or hidden allocating runtime call.
Fixed stack slots and static storage are permitted. Unknown effects, indirect
calls without a proof, and allocator calls make certification fail at compile
time. Macro expansion occurs before effect checking, so host allocations made
while expanding a macro do not count as target allocations. **A first hosted
managed heap and transitive `without-allocation` effect check are implemented
in M4. General stack, static, and arena allocation forms remain specified but
unimplemented.**

## 7. Compilation stages and target separation

The stages are read, macro expand, semantic analysis, typed HIR, portable SSA,
verified LIR,
target lowering, object writing, linking, loading, and execution. Compile-time
code runs on the build host. Target queries such as pointer width and
endianness are compile-time data; querying them must not execute target code.
Target architecture, ABI, OS, and object format are separate descriptors.

The compiler emits normal object symbols and relocations. An ordinary `defun`
with `returns` and `c-export` declarations exports a function under the
selected C ABI. `ffi:import-function` declares an imported C signature, and
`ffi:call` marks each invocation. `ffi:source` includes a local C translation
unit in the resulting relocatable object on a supported hosted target. If no
source file is included, the C symbol remains an unresolved link dependency.
`ffi:import-data` and `ffi:export-data` declare C data symbols;
`ffi:address-of` obtains their typed raw address. On the Linux and Windows
targets, the driver can invoke the selected linker or archiver for an
executable, shared library, or static archive with explicit extra link inputs.
The earlier `psl:defun/c` and `psl:extern-function` spellings are also accepted
by Stage 0.
A versioned 64-bit tagged-value and root ABI exists for the M4 hosted runtime;
the complete ABI for independently compiled dynamic Lisp components remains a
later feature. Internal Lisp calls may use a private convention. Freestanding
objects must not acquire hidden libc, GC, or OS dependencies. A compiler error
must identify the unsupported form or violated rule and must not claim that an
object was successfully produced.

## 8. Core conformance examples

```lisp
;; Ordinary DEFUN carries the C-facing type information in declarations.
(defun add (a b)
  (declare (type u64 a b)
           (returns u64)
           (c-export :c))
  (wrap+ a b))

;; Zero is true, and LET initializers see the outer binding of x.
(defun choose (x)
  (declare (type u64 x)
           (returns u64)
           (c-export :c))
  (let ((x 1) (y x))
    (if 0 (wrap+ x y) 0)))

;; Compile-time macro execution can generate target expressions.
(defmacro twice (x) `(wrap+ ,x ,x))
```

The [smoke test](../tests/smoke.sh) runs corresponding integer, macro,
pointer, C ABI, layout, and linking cases through generated ELF objects and C
harnesses.
Unsupported allocation forms and other later features must fail clearly,
not emit code with guessed semantics. The [hosted runtime contract](runtime.md)
records the implemented M4 subset.
