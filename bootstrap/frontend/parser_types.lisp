;; Layout declarations shared by compiler code and hosted driver storage.
(include "reader_types.lisp")
(include "environment/reader_types.lisp")

(defcstruct psl_ast_node
  (kind u32)
  (start usize)
  (length usize)
  (first usize)
  (last usize)
  (next usize))

(defcstruct psl_parser
  (scanner (ptr psl_scanner))
  (token (ptr psl_token))
  (has_token u8)
  (nodes (ptr psl_ast_node))
  (count usize)
  (capacity usize)
  (error u32)
  (environment (ptr native_reader_environment)))
