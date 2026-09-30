(ffi:import-function "check_c_strings"
  ((first (ptr u8)) (second (ptr u8))) -> c-int)

(defun answer ()
  (declare (returns c-int) (c-export :c))
  (ffi:call check_c_strings
            (ffi:c-string "portable")
            (ffi:c-string "systems lisp")))
