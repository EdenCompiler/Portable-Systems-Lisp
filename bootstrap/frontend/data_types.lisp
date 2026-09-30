;; Imported data declarations are separate from function signatures. Names
;; retain exact C linker spelling and TYPE-AST identifies the pointed value.
(defcstruct native_data_import
  (name (ptr u8))
  (name_length usize)
  (type_ast usize)
  (size usize)
  (alignment usize)
  (referenced u8))
