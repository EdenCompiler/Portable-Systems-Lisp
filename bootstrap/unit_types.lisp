;; Caller-owned state for one compilation unit. On failure, phase identifies
;; the pass, form identifies an AST node, and index identifies a signature.
;; Contexts and arenas must be freshly initialized for each invocation.
(defcstruct native_unit_result
  (phase usize)
  (form usize)
  (index usize))

