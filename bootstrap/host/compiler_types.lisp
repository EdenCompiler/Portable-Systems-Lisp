(include "driver_types.lisp")
(include "../unit_types.lisp")

(defcstruct native_compiler_state
  (driver native_driver)
  (result native_unit_result)
  (optimization u32))
