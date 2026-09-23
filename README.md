# Portable Systems Lisp

Portable Systems Lisp (PSL) is an experimental native compiler for Lisp code
that works with machine integers, raw pointers, and C functions. It uses SBCL
to compile source files into relocatable object files. The language is being
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
[the standalone example](examples/standalone.lisp) for the source file.

## Try it

On x86-64 Linux, install SBCL and a C compiler, then run from the repository
root:

```sh
./pslcc -c examples/add.lisp -o /tmp/psl-add.o
cc examples/harness.c /tmp/psl-add.o -o /tmp/psl-add
/tmp/psl-add
```

The C harness calls the exported PSL function and exits successfully when its
result is correct. There is no separate compiler build step: `pslcc` starts
the Stage 0 compiler under SBCL.

## Source and C interop

PSL extensions such as `u64`, `returns`, and `wrap+` are available without a
package prefix. C boundaries have explicit `ffi:` forms:

```lisp
(ffi:source "ffi_math.c")
(ffi:import-function "scale_c" ((value u64) (factor u64)) -> u64)

(defun scale_then_add (value)
  (declare (type u64 value)
           (returns u64)
           (c-export :c))
  (wrap+ (ffi:call scale_c value 2) 2))
```

`ffi:source` includes a local C file in the generated object. Imported C
functions use `ffi:call`; calls between PSL functions use ordinary Lisp call
syntax. See [the complete C import example](examples/ffi_source.lisp).

## Compiler interface

```text
./pslcc -c source.lisp -o output.o [--target=TARGET]
        [--profile=hosted|freestanding] [-O0|-O1]
        [--dump-ir=hir|ssa|lir|all]
```

The default target is `x86_64-linux-gnu`; `x86_64-none-elf` can also produce
an ELF64 object. Both profiles currently compile the same typed subset.
`-O1` is the default optimization level. The compiler emits `.o` files;
linking an executable is currently done with a system linker such as `cc`.

## Project status

The core specification, first native object, and compiler foundation
milestones are complete. The compiler has typed HIR, SSA, and low-level IR,
with a shared frontend and an x86-64 ELF object writer. C function imports
and exports work for supported integer and pointer signatures. The larger C
integration milestone remains in progress.

The hosted profile is **not yet an ANSI Common Lisp implementation**. There
is no hosted runtime, GC, or dynamic Lisp object model yet. The freestanding
target currently emits a relocatable object, not a bootable image. See the
[implemented core](docs/core.md) for exact accepted forms and limits, and the
[roadmap](docs/roadmap.md) for milestone status.

## Documentation and tests

- [Language specification](docs/specification.md) — intended semantics and profiles.
- [Implemented core](docs/core.md) — what the current compiler accepts.
- [Compiler pipeline](docs/compiler.md) and [source layout](docs/architecture.md).
- [Engineering roadmap](docs/roadmap.md) and [contributor instructions](AGENTS.md).

Run `sh tests/smoke.sh` to check object generation, C interoperability, and
deterministic output. The test suite needs SBCL, `cc`, `readelf`, `nm`, and
`cmp`.
