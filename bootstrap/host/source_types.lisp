(include "../frontend/parser_types.lisp")

;; NEXT is opaque because the native layout pass registers earlier types only.
(defcstruct native_source_file
  (path (ptr u8))
  (active c-int)
  (next (ptr void)))

(defcstruct native_source_unit
  (bytes (ptr u8))
  (length usize)
  (capacity usize)
  (files (ptr native_source_file))
  (search_cursor (ptr native_source_file))
  (search_result (ptr native_source_file)))

(defcstruct native_source_frame
  (file (ptr native_source_file))
  (bytes (ptr u8))
  (length usize)
  (scanner psl_scanner)
  (token psl_token)
  (parser psl_parser)
  (root usize)
  (status c-int))
