(include "types.lisp")
;; The immutable type catalog is shared by SSA and LIR. Only call argument
;; links carry operand metadata here; ordinary operand edges live in the IR.
(defun ir_type_at (types reference)
  (declare (type (ptr native_ir_type) types)
           (type usize reference) (returns (ptr native_ir_type)))
  (pointer+ types (wrap-cast isize (wrap- reference 1))))

