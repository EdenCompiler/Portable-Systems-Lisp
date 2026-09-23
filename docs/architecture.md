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
    reader.lisp         source input, declarations, machine types
    layout.lisp         packed structure layout and field lookup
    analyze.lisp        macro expansion and typed semantic analysis
  ir/
    hir.lisp            typed HIR data structures
    types.lisp          machine type queries and pointer qualifiers
    lower.lisp          typed HIR to portable LIR
  backend/
    x86-64.lisp         LIR to x86-64 machine code and ABI argument mapping
  object/
    elf64.lisp          ELF sections, symbols, and relocations
  ffi/
    toolchain.lisp      explicit C source compilation and object merge
```

`compile-source` coordinates reader → analyzer → LIR lowering → backend →
object writer. The frontend does not encode machine instructions. The object
writer consumes encoded functions and relocations rather than source forms.
The FFI toolchain runs only when source explicitly declares a C translation
unit; ordinary typed compilation needs no C compiler until final linking.
The current LIR uses virtual registers and explicit branches; SSA and
optimization passes are future work.

This separation follows the broad division used by the [LLVM source tree](https://llvm.org/docs/GettingStarted.html),
which has distinct IR, code generation, target, and object-related areas, and
the [Rust compiler source tree](https://rustc-dev-guide.rust-lang.org/compiler-src.html),
which separates compiler components from its libraries and code-generation
backend. PSL uses a much smaller tree because only one target and one object
format exist today. Add a directory when it contains real code, rather than
creating empty placeholders for planned targets or runtimes.

Each major module has its own Lisp package. `psl.compiler` is the public
library entry point and coordinates the pipeline. `psl` contains source-level
systems extensions. Source files get these names imported into a temporary
package, while standard Common Lisp symbols retain their normal meaning.
