(include "driver_types.lisp")
(include "../unit_types.lisp")
(include "c_source_types.lisp")

(defcstruct native_cli_options
  (source (ptr u8))
  (output (ptr u8))
  (optimization u32)
  (target u32)
  (profile u32)
  (compile_only u32)
  (output_option u32)
  (paths usize)
  (cursor usize))

(defcstruct native_compiler_state
  (driver native_driver)
  (result native_unit_result)
  (c_sources (ptr native_c_source_path))
  (optimization u32)
  (target u32)
  (profile u32)
  (options native_cli_options))
