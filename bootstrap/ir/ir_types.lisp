;; The immutable type catalog is shared by SSA and LIR. Only call argument
;; links carry operand metadata here; ordinary operand edges live in the IR.
(defcstruct native_ir_type
  (kind u32)
  (scalar_code u32)
  (pointee usize)
  (left usize)
  (right usize))

(defcstruct native_scalar_op
  (kind u32)
  (scalar_code u32)
  (pointee usize)
  (value u64)
  (left usize)
  (right usize)
  (target usize)
  (source usize))

(defun ir_type_at (types reference)
  (declare (type (ptr native_ir_type) types)
           (type usize reference) (returns (ptr native_ir_type)))
  (pointer+ types (wrap-cast isize (wrap- reference 1))))

