(include "compiler_types.lisp")

;; The separately compiled PSL modules expose these typed C ABI entry points.
(ffi:import-function "native_read_source_unit"
  ((path (ptr u8)) (length (ptr usize))
   (c-sources (ptr (ptr native_c_source_path)))) -> (ptr u8))
(ffi:import-function "native_prepare_driver" ((driver (ptr native_driver))) -> c-int)
(ffi:import-function "native_release_driver" ((driver (ptr native_driver))) -> c-int)
(ffi:import-function "native_compile_unit"
  ((context (ptr native_compile_context)) (object (ptr byte_buffer))
   (result (ptr native_unit_result))) -> c-int)

;; Object output is another PSL unit; C still renders selected diagnostics.
(ffi:import-function "native_host_write_object"
  ((path (ptr u8)) (object (ptr byte_buffer))) -> c-int)
(ffi:import-function "native_host_merge_c_sources"
  ((path (ptr u8)) (object (ptr byte_buffer))
   (sources (ptr native_c_source_path)) (target u32)) -> c-int)
(ffi:import-function "native_host_report_error"
  ((kind u32) (text (ptr u8)) (length usize) (position usize)) -> void)
(ffi:import-function "calloc" ((count usize) (size usize)) -> (ptr void))
(ffi:import-function "free" ((memory (ptr void))) -> void)
