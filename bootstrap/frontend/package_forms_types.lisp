;; Scratch state for ordered build-host package source forms.
(include "parser_types.lisp")
(defcstruct native_package_context
  (parser (ptr psl_parser))
  (source (ptr u8))
  (environment (ptr native_ct_environment))
  (name (ptr u8))
  (offset usize)
  (length usize)
  (package usize)
  (error u32)
  (seen u32))
