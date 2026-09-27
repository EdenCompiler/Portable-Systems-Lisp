;; Layout declarations shared by compiler code and hosted driver storage.

(defcstruct native_hir_node
  (kind u32)
  (type_code u32)
  (value u64)
  (left usize)
  (right usize)
  (target usize)
  (source usize)
  (scalar_code u32)
  (pointee usize))

(defcstruct native_hir_arena
  (nodes (ptr native_hir_node))
  (count usize)
  (capacity usize)
  (error u32))
