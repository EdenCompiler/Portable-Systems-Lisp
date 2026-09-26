(defun invalid_add (byte word)
  (declare (type u8 byte) (type u64 word) (returns u64) (c-export :c))
  (wrap+ byte word))
