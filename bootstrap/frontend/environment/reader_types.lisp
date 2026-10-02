(include "types.lisp")

;; Keep source spans in the original AST. The side table assigns each node a
;; symbol identity before semantic collection and records its originating node
;; for future macro diagnostics. Numeric and string nodes have symbol ID zero.
(defcstruct native_source_identity
  (symbol usize)
  (origin usize))

(defcstruct native_reader_environment
  (environment (ptr native_ct_environment))
  (identities (ptr native_source_identity))
  (capacity usize)
  (count usize)
  (cursor usize)
  (error usize)
  (failure u32))
