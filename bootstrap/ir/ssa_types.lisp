;; Layout declarations shared by compiler code and hosted driver storage.
(include "types.lisp")

(defcstruct native_ssa_value
  (kind u32)
  (scalar_code u32)
  (pointee usize)
  (value u64)
  (left usize)
  (right usize)
  (target usize)
  (source usize)
  (block usize)
  (next usize)
  (predecessor_left usize)
  (predecessor_right usize))

(defcstruct native_ssa_block
  (first usize)
  (last usize)
  (terminator u32)
  (condition usize)
  (target_left usize)
  (target_right usize)
  (result usize)
  (visit u8))

(defcstruct native_ssa_arena
  (values (ptr native_ssa_value))
  (types (ptr native_ir_type))
  (value_count usize)
  (value_capacity usize)
  (blocks (ptr native_ssa_block))
  (block_count usize)
  (block_capacity usize)
  (current usize)
  (error u32))
