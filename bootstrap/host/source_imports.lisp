(include "source_types.lisp")

;; Separate PSL translation units share the documented exported C ABI.
(ffi:import-function "parser_next" ((parser (ptr psl_parser))) -> usize)
(ffi:import-function "native_source_form_kind"
  ((parser (ptr psl_parser)) (bytes (ptr u8)) (root usize)) -> u32)
(ffi:import-function "native_source_include_size"
  ((parser (ptr psl_parser)) (bytes (ptr u8)) (root usize)) -> usize)
(ffi:import-function "native_source_include_copy"
  ((parser (ptr psl_parser)) (bytes (ptr u8)) (root usize)
   (output (ptr u8)) (capacity usize)) -> c-int)

;; File input is another PSL unit. The OS adapter canonicalizes paths, exposes
;; platform path policy, and renders source diagnostics.
(ffi:import-function "native_source_read_file"
  ((path (ptr u8)) (length (ptr usize))) -> (ptr u8))
(ffi:import-function "native_source_canonical_path" ((path (ptr u8))) -> (ptr u8))
(ffi:import-function "native_source_windows_paths" () -> c-int)
(ffi:import-function "native_source_report_error" ((kind u32) (path (ptr u8))) -> void)

(ffi:import-function "malloc" ((size usize)) -> (ptr void))
(ffi:import-function "calloc" ((count usize) (size usize)) -> (ptr void))
(ffi:import-function "realloc" ((memory (ptr void)) (size usize)) -> (ptr void))
(ffi:import-function "free" ((memory (ptr void))) -> void)
(ffi:import-function "strlen" ((text (ptr u8))) -> usize)
(ffi:import-function "strcmp" ((left (ptr u8)) (right (ptr u8))) -> c-int)
(ffi:import-function "strrchr" ((text (ptr u8)) (byte c-int)) -> (ptr u8))
(ffi:import-function "memcpy"
  ((destination (ptr void)) (source (ptr void)) (size usize)) -> (ptr void))
