(defcstruct sample
  (tag u8)
  (data (ptr u8))
  (count u32))

(defcstruct outer
  (head u16)
  (inner sample)
  (tail u8))

(defun answer ()
  (declare (returns u64) (c-export :c))
  42)
