(include "../parser_types.lisp")

;; A build-host rewrite owns new nodes in the parser arena. Identities remain
;; language symbols; source origin references are separate from generated nodes.
(defcstruct native_tree_context
  (parser (ptr psl_parser))
  (reader (ptr native_reader_environment))
  (origin usize)
  (depth usize)
  (limit usize)
  (cursor usize)
  (error u32)
  (remaining usize)
  (last usize))
