;; Pointee references carry pointer storage qualifiers in compiler metadata.
;; The remaining 62 bits retain the parser index; unqualified references keep
;; their existing representation. These tags never reach target addresses.

(defun source_pointer_base (reference)
  (declare (type usize reference) (returns usize))
  (bits-and reference #x3fffffffffffffff))

(defun source_pointer_flags (reference)
  (declare (type usize reference) (returns usize))
  (bits-and reference #xc000000000000000))

(defun source_pointer_const_p (reference)
  (declare (type usize reference) (returns c-int))
  (if (= (bits-and reference #x4000000000000000) 0) 0 1))

(defun source_pointer_with_flags (type pointer)
  (declare (type usize type pointer) (returns usize))
  (wrap+ (source_pointer_base type) (source_pointer_flags pointer)))
