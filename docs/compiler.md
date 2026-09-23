# Stage 0 compiler pipeline

The SBCL library exposes the same stages used by `pslcc`:

```lisp
(let ((unit (psl.compiler:read-unit "examples/basic/add.lisp")))
  (unwind-protect
       (let ((program (psl.compiler:analyze-unit unit)))
         (psl.compiler:lower-unit program)
         (psl.compiler:optimize-unit program)
         (psl.compiler:linearize-unit program)
         (psl.compiler:emit-unit program "/tmp/add.o"))
    (psl.compiler:dispose-unit unit)))
```

`read-unit` owns a temporary source package; callers dispose it after analysis
and object emission. `analyze-unit` checks typed HIR, `lower-unit` builds and
checks SSA, `optimize-unit` checks SSA after its passes, and `linearize-unit`
checks LIR. `emit-unit` rechecks LIR before encoding so later library edits
cannot bypass verification. `compile-source`
coordinates these calls and always disposes the source package.
`psl.compiler:compile-and-link` runs that pipeline and uses the selected
native linker or archiver for an executable, static archive, or shared
library. Its `:inputs` list names additional C objects or libraries.
`compile-source` returns the output path and, as a second value, the hosted
runtime modules requested by the source. `compilation-runtime-modules` exposes
the same list after `analyze-unit`. Linked artifacts include the transitive
module dependencies; object-only compilation leaves their symbols unresolved.

## IR contracts

- HIR carries machine types and source locations. Its verifier checks literals,
  lexical bindings, calls, arithmetic, memory operations, and function returns.
- SSA has one definition per value, explicit block terminators, and `phi`
  inputs named by predecessor block. The verifier checks type consistency,
  predecessor sets, reachability, dominance, and use-before-definition.
- The optimizer inlines small, single-block leaf functions, folds exact machine
  constants with their width and signedness, and removes unused pure values.
  Calls, stores, and volatile loads stay live. `-O0` skips these passes; `-O1`
  enables them and is the default.
- LIR is a linear stream of typed virtual-register instructions and labels.
  `phi` inputs become copies on the corresponding control-flow edges. Its
  verifier checks register types, branch targets, definite assignment, and
  returning paths before the backend encodes instructions.
- Target selection is separate from IR. The x86 backend takes LIR plus a
  contract for System V or Microsoft x64 argument registers, the 64-bit
  pointer model, stack alignment, and object format. The
  frontend also supplies target-specific C aggregate layout metadata. Generic
  optimization passes do not encode target instructions or object sections.

`--dump-ir=hir|ssa|lir|all` prints the selected stage to standard output.
Locations use `path:line:column` for source forms. Macro-generated forms inherit
the location of their invocation when they have no direct source location.

## M2 verification

`sh tests/smoke.sh` runs the same C behavior tests under `-O0` and `-O1`,
checks deterministic objects, observes local-call inlining and constant
folding, and checks that effectful C calls and volatile loads remain. The suite
also feeds malformed HIR, SSA, and LIR to the public verifiers and checks a
precise nested-form diagnostic. The supported language and target matrix is in
[the roadmap](roadmap.md).
