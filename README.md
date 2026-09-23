# Portable Systems Lisp

Portable Systems Lisp (PSL) is an experimental native compiler for Lisp code
that works with machine integers, raw pointers, and C functions. It uses SBCL
to compile source files into ELF object files and, on x86-64 Linux, link
executables and libraries. The language is being
built toward a hosted Common Lisp implementation and a freestanding systems
profile; today, the compiler implements a small, typed subset of that design.

```lisp
(defun add42 (value)
  (declare (type u64 value)
           (returns u64)
           (c-export :c))
  (wrap+ value 42))
```

This defines an ordinary Lisp function, gives it a machine-width signature,
and exports `add42` for C callers. `wrap+` requests explicit unsigned
wraparound; standard Common Lisp operators keep their usual meaning. See
[the standalone example](examples/basic/standalone.lisp) for the source file.

## Try it

On x86-64 Linux, install SBCL and a C compiler for linking, then run from the
repository root:

```sh
./pslcc examples/native/arithmetic.lisp -o /tmp/psl-arithmetic
/tmp/psl-arithmetic
echo $?
```

The program is written entirely in Lisp and exits successfully when its
arithmetic check passes. There is no separate compiler build step: `pslcc`
starts the Stage 0 compiler under SBCL. It invokes the system linker to make
an executable; compiling with `-c` needs no C compiler. See the
[native examples](examples/README.md#native-lisp-programs) for recursion,
macros, and packed layout programs.

## Source and C interop

PSL extensions such as `u64`, `returns`, and `wrap+` are available without a
package prefix. C boundaries have explicit `ffi:` forms:

```lisp
(ffi:source "math.c")
(ffi:import-function "scale_c" ((value u64) (factor u64)) -> u64)

(defun scale_then_add (value)
  (declare (type u64 value)
           (returns u64)
           (c-export :c))
  (wrap+ (ffi:call scale_c value 2) 2))
```

`ffi:source` includes a local C file in the generated object. Imported C
functions use `ffi:call`; calls between PSL functions use ordinary Lisp call
syntax. Data symbols use `ffi:import-data`, `ffi:export-data`, and
`ffi:address-of`. See the [C import example](examples/ffi/source_import.lisp),
the [shared data example](examples/ffi/shared_data.lisp), and the
[example index](examples/README.md).

## Compiler interface

```text
./pslcc -c source.lisp -o output.o [--target=TARGET]
        [--profile=hosted|freestanding] [-O0|-O1]
        [--dump-ir=hir|ssa|lir|all]
./pslcc [--emit=exe|static|shared] source.lisp -o OUTPUT
        [--link-input=FILE]...
```

The default target is `x86_64-linux-gnu`; `x86_64-none-elf` can also produce
an ELF64 object. Both profiles compile the typed subset; `hosted` also accepts
the first managed-value facilities.
`-O1` is the default optimization level. `-c` writes a relocatable `.o` without
linking. On native x86-64 Linux, the second form invokes `cc` or `ar` for an
executable, `.a`, or `.so`. Extra C objects and libraries are explicit link
inputs. The library API exposes both compilation and linking.

## Project status

The core specification, first native object, compiler foundation, first C ABI
path, and first modular hosted runtime are implemented. The compiler has typed
HIR, SSA, and low-level IR,
with a shared frontend and an x86-64 ELF object writer. C calls support
integer and pointer values, `float`/`double`, stack arguments, and small
scalar-field C structs by value. Naturally aligned C struct layouts and data
symbols are supported. Hosted source can also use tagged values, conses,
strings, symbols, packages, one-argument lexical closures, two values, and a
basic collector. See the [implemented core](docs/core.md) and
[runtime contract](docs/runtime.md) for exact limits.

The hosted profile is **not yet an ANSI Common Lisp implementation**. There
is no numeric tower, conditions, CLOS, streams, or general `eval` yet. The
freestanding target currently emits a relocatable object, not a bootable image.
See the [roadmap](docs/roadmap.md) for milestone status.

## Documentation and tests

- [Language specification](docs/specification.md) — intended semantics and profiles.
- [Implemented core](docs/core.md) — what the current compiler accepts.
- [Compiler pipeline](docs/compiler.md) and [source layout](docs/architecture.md).
- [Hosted runtime](docs/runtime.md) and [examples](examples/README.md).
- [Engineering roadmap](docs/roadmap.md) and [contributor instructions](AGENTS.md).

Run `sh tests/smoke.sh` to check object generation, C interoperability, and
deterministic output. The test suite needs SBCL, `cc`, `ar`, `readelf`, `nm`,
and `cmp`.
