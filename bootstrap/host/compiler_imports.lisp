(include "compiler_types.lisp")

;; The separately compiled PSL modules expose these typed C ABI entry points.
(ffi:import-function "native_read_source_unit"
  ((path (ptr u8)) (length (ptr usize))
   (c-sources (ptr (ptr native_c_source_path)))) -> (ptr u8))
(ffi:import-function "native_prepare_driver" ((driver (ptr native_driver))) -> c-int)
(ffi:import-function "native_prepare_driver_capacity"
  ((driver (ptr native_driver)) (capacity usize)) -> c-int)
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
(ffi:import-function "native_host_link_artifact"
  ((path (ptr u8)) (object (ptr byte_buffer))
   (sources (ptr native_c_source_path)) (target u32) (profile u32)
   (runtime_modules u64) (kind u32) (inputs (ptr (ptr u8)))
   (input_count usize) (startup_kind u32) (entry (ptr u8))
   (linker_script (ptr u8)) (map_file (ptr u8))) -> c-int)
(ffi:import-function "native_host_link_supported" () -> c-int)
(ffi:import-function "native_host_runtime_roots"
  ((target u32) (sources (ptr native_c_source_path))
   (inputs (ptr (ptr u8))) (input_count usize)) -> u64)
(ffi:import-function "native_host_write_ir"
  ((bytes (ptr u8)) (length usize)) -> c-int)
(ffi:import-function "native_host_report_error"
  ((kind u32) (text (ptr u8)) (length usize) (position usize)) -> void)
(ffi:import-function "calloc" ((count usize) (size usize)) -> (ptr void))
(ffi:import-function "free" ((memory (ptr void))) -> void)
