(ffi:import-function "take_text" ((text (ptr u8))) -> c-int)
(defun answer ()
  (declare (returns c-int) (c-export :c))
  (ffi:call take_text (ffi:c-string "one" "two")))
