(defcstruct cell (value u8))
(defun bad (pointer)
  (declare (type (ptr cell :const) pointer) (returns u8))
  (store (field-pointer pointer 'value) 1))
