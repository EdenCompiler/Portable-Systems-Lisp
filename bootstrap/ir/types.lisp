;; Layout declarations shared by compiler code and hosted driver storage.

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
