(include "driver_types.lisp")
(include "../unit_types.lisp")
(include "c_source_types.lisp")

(defcstruct native_compiler_state
  (driver native_driver)
  (result native_unit_result)
  (c_sources (ptr native_c_source_path))
  (optimization u32)
  (target u32))
