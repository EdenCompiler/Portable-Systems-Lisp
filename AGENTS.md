# Repository instructions for coding agents

Portable Systems Lisp is a staged compiler project. Read `README.md`,
`docs/core.md`, `docs/architecture.md`, and `docs/roadmap.md` before changing
language behavior or target support. Treat `docs/core.md` as the implemented
contract and `docs/roadmap.md` as planned work; neither a CLI option nor a
folder name proves a feature is complete.

## How to work

- Implement one reviewable vertical slice at a time. State the behavior it adds,
  the target/profile on which it works, and the evidence that verifies it.
- Keep functions small and single-purpose. Extract parsing, validation,
  lowering, encoding, and object writing into named helpers when a function
  mixes responsibilities. Prefer clear data flow over clever Lisp macros in
  compiler implementation code.
- Keep the CLI thin. Put reusable compilation logic behind package exports,
  load new modules in `src/load.lisp`, and declare packages and exports in
  `src/package.lisp`.
- Preserve the module boundaries: source and macro handling in `frontend/`,
  target-independent representations in `ir/`, CPU encoding in `backend/`,
  object formats in `object/`, target selection in `target.lisp`, and pipeline
  coordination in `driver.lisp`.
- Add a directory or package when it owns working code and a clear interface.
  Update `docs/architecture.md` when dependencies or ownership change.
- Update `docs/core.md` for implemented language semantics and
  `docs/roadmap.md` for milestone status, evidence, and remaining limits.

## Language and portability rules

- Preserve standard Common Lisp meanings in the hosted design. Define machine
  integers, pointer operations, layout controls, and other extensions in the
  `psl` package; import their names into source units for natural spelling.
  In particular, do not redefine ordinary `cl:+` as wrapping arithmetic
  or treat integer zero as false in `if`.
- Run compile-time macros on the build host; do not require the target program
  to execute during cross compilation. Source macros are trusted build code.
- Keep architecture, ABI, OS, and object format distinct. Do not add x86-64,
  Linux, ELF, pointer-width, or endianness assumptions to the frontend or
  target-independent IR.
- Keep freestanding output free of implicit libc, GC, hosted startup, and OS
  dependencies. A feature requiring runtime support must declare and link that
  support explicitly.
- Keep C boundaries visible in source: use `ffi:source` for included C files,
  `ffi:import-function` for C signatures, and `ffi:call` for imported calls.
  Keep ordinary Lisp calls and arithmetic unqualified. Preserve Common Lisp
  names such as `load` and `export` when adding shorthand for PSL extensions.
- Do not promise allocation-free execution based on convention. Implement an
  effect check that rejects unknown or allocating calls before exposing a
  `no-allocation` guarantee.
- Do not advertise a target as executable when it only emits an object file.
  Do not claim ANSI Common Lisp conformance without the M9 gate.

## Verification

- Run `sh tests/smoke.sh` after compiler changes. Add focused tests when a new
  behavior or regression risk cannot be checked by the existing C harness,
  object inspection, or deterministic-output check.
- Verify ABI and data layout against compiled C programs; verify object formats
  with standard inspection tools; verify freestanding and cross-target claims
  with an emulator or runner for that target.
- Keep test fixtures independent of compiler internals. Do not add tests that
  merely repeat an implementation algorithm without checking observable output.
- Keep `README.md` examples executable. Report incomplete milestones plainly;
  do not leave placeholder code or unsupported claims in the support matrix.
