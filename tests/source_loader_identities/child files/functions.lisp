(defun loader_answer ()
  (declare (psl:returns psl:c-int) (psl:c-export :c))
  (psl:wrap+ (psl:deref (ffi:address-of loader_bias)) 12))
