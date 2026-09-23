# Compiler source organization

The Stage 0 compiler keeps the command-line entry point thin and loads modules
in dependency order:

```text
src/
  cli.lisp              command-line parsing
  load.lisp             ordered module loading
  package.lisp          public PSL names and compiler package
  common.lisp           shared diagnostics
  binary.lisp           little-endian byte-buffer operations
  target.lisp           architecture, ABI, OS, and object-format selection
  driver.lisp           compilation pipeline entry point
  frontend/
    layout.lisp         packed structure layout and field lookup
    reader.lisp         source input, declarations, machine types
    runtime.lisp        hosted operations and module requests
    closures.lisp       lexical capture and closure functions
    strings.lisp        hosted UTF-8 source literals
    multiple-values.lisp  two-value source forms
    analyze.lisp        macro expansion and typed semantic analysis
    effects.lisp        transitive allocation-effect checking
  ir/
    hir.lisp            typed HIR data structures
    types.lisp          machine type queries and pointer qualifiers
    ssa.lisp            portable CFG, SSA values, and explicit joins
    lower.lisp          typed HIR to SSA and SSA to portable LIR
    verify/             HIR, SSA, and LIR invariant checks
    optimize.lisp       inlining, constant folding, and dead-code removal
    dump.lisp           stable, readable IR inspection
  backend/
    x86-64.lisp         LIR to x86-64 machine code and ABI argument mapping
    win64-abi.lisp      Microsoft x64 calls, returns, and shadow space
  object/
    elf64.lisp          ELF sections, symbols, and relocations
    coff.lisp           COFF sections, symbols, relocations, and unwind records
  ffi/
    toolchain.lisp      C source and selected runtime module linking
runtime/
  psl_runtime.h         versioned hosted value and root ABI
  gc.c                  mark-and-sweep collector
  startup.c             lazy hosted initialization
  platform_linux.c      Linux stack bounds
  platform_windows.c    Windows stack bounds
  value.c, cons.c, string.c, symbol.c, package.c, closure.c, values.c
                         separately selected dynamic facilities
```

`compile-source` coordinates reader → analyzer → verified HIR → CFG/SSA →
optional optimization → verified LIR → backend → object writer. The frontend
does not encode machine instructions. The x86 backend receives LIR and an
explicit target contract containing ABI registers, pointer width, stack
alignment, and object format. The ELF and COFF writers consume encoded
functions and relocations rather than source forms.
The FFI toolchain runs only when source explicitly declares a C translation
unit or the caller requests a linked artifact. Ordinary typed `-c` compilation
needs no C compiler. Hosted dynamic source records runtime module dependencies;
the linker compiles their transitive closure while typed programs select none.
The frontend computes C structure layout and passes the
supported aggregate ABI metadata to the backend. The object writer owns data
symbols and GOT relocations on Linux, while COFF uses relative relocations and
`.pdata`/`.xdata` unwind records. The selected system linker and archiver
produce Linux or Windows artifacts.
The SSA representation has basic blocks, typed values, terminators, and `phi`
joins. The current language subset has conditional branches but no loop form.
LIR uses virtual registers and explicit labels after `phi` edge copies are
placed. See [the compiler pipeline](compiler.md) for stage APIs and invariants.

This separation follows the broad division used by the [LLVM source tree](https://llvm.org/docs/GettingStarted.html),
which has distinct IR, code generation, target, and object-related areas, and
the [Rust compiler source tree](https://rustc-dev-guide.rust-lang.org/compiler-src.html),
which separates compiler components from its libraries and code-generation
backend. PSL uses a much smaller tree because it has one CPU backend and two
object formats today. Add a directory when it contains real code, rather than
creating empty placeholders for planned targets or runtimes.

Each major compiler module has its own Lisp package. `psl.compiler` is the public
library entry point and coordinates the pipeline. `psl` contains source-level
systems extensions. Source files get these names imported into a temporary
package, while standard Common Lisp symbols retain their normal meaning.
