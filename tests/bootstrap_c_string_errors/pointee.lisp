(ffi:import-function "take_words" ((words (ptr s32))) -> c-int)
(defun answer ()
  (declare (returns c-int) (c-export :c))
  (ffi:call take_words (ffi:c-string "wrong pointee")))
