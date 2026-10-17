;; Layout declarations shared by compiler code and hosted driver storage.
(include "reader_types.lisp")
(include "environment/reader_types.lisp")

(defcstruct psl_ast_node
  (kind u32)
  (start usize)
  (length usize)
  (first usize)
  (last usize)
  (next usize)
  ;; Kind 11 is a compiler-generated integer literal. These fields are
  ;; payload, never child references; source spans remain real zero-length
  ;; origins and the reader identity side table keeps the macro origin.
  (integer_magnitude u64)
  (integer_negative u8))

(defcstruct psl_parser
  (scanner (ptr psl_scanner))
  (token (ptr psl_token))
  (has_token u8)
  (nodes (ptr psl_ast_node))
  (count usize)
  (capacity usize)
  (error u32)
  (environment (ptr native_reader_environment)))
