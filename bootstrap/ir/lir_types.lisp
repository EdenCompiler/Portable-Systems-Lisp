;; Layout declarations shared by compiler code and hosted driver storage.
(include "types.lisp")

(defcstruct native_lir_instruction
  (kind u32)
  (scalar_code u32)
  (pointee usize)
  (value u64)
  (left usize)
  (right usize)
  (target usize)
  (source usize)
  (destination usize))

(defcstruct native_lir_block
  (first usize)
  (last usize)
  (visit u8))

(defcstruct native_lir_arena
  (instructions (ptr native_lir_instruction))
  (count usize)
  (capacity usize)
  (types (ptr native_ir_type))
  (value_count usize)
  (value_capacity usize)
  (blocks (ptr native_lir_block))
  (label_count usize)
  (label_capacity usize)
  (error u32))
