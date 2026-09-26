(defun add_u8 (left right)
  (declare (type u8 left right) (returns u8) (c-export :c))
  (wrap+ left right))

(defun zero_u8 ()
  (declare (returns u8) (c-export :c))
  -0)

(defun multiply_u16 (left right)
  (declare (type u16 left right) (returns u16) (c-export :c))
  (wrap* left right))

(defun subtract_u32 (left right)
  (declare (type u32 left right) (returns u32) (c-export :c))
  (wrap- left right))

(defun smaller_s8 (left right)
  (declare (type s8 left right) (returns s8) (c-export :c))
  (if (< left right) left right))

(defun increment-s8 (value)
  (declare (type s8 value) (returns s8))
  (wrap+ value 1))

(defun nested_s8 (value)
  (declare (type s8 value) (returns s8) (c-export :c))
  (smaller_s8 (increment-s8 value) -1))

(defun add_s16 (left right)
  (declare (type s16 left right) (returns s16) (c-export :c))
  (wrap+ left right))

(defun add_c_int (left right)
  (declare (type c-int left right) (returns c-int) (c-export :c))
  (wrap+ left right))

(defun smaller_s32 (left right)
  (declare (type s32 left right) (returns s32) (c-export :c))
  (if (< left right) left right))

(defun negate_s64 (value)
  (declare (type s64 value) (returns s64) (c-export :c))
  (wrap- 0 value))

(defun minimum_s64 ()
  (declare (returns s64) (c-export :c))
  -9223372036854775808)

(defun smaller_isize (left right)
  (declare (type isize left right) (returns isize) (c-export :c))
  (if (< left right) left right))
