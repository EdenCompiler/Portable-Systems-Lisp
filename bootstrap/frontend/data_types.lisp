;; Data declarations are separate from function signatures. Names retain exact
;; C linker spelling and TYPE-AST identifies the pointed value. A defined entry
;; carries the scalar bits written to the object's data section.
(defcstruct native_data_import
  (name (ptr u8))
  (name_length usize)
  (type_ast usize)
  (size usize)
  (alignment usize)
  (bytes (ptr u8))
  (initial u64)
  (defined u8)
  (global u8)
  (referenced u8))
