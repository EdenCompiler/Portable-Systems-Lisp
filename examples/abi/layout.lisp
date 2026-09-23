(defcstruct inner
  (tag c-uchar)
  (count c-ulong))

(defcstruct outer
  (head c-uchar)
  (inner inner)
  (tail c-ushort))

(defcstruct mixed
  (tag c-uchar)
  (measure c-float)
  (context (ptr u8))
  (ratio c-double))

(defun outer_size ()
  (declare (returns usize) (c-export :c))
  (sizeof 'outer))

(defun outer_alignment ()
  (declare (returns usize) (c-export :c))
  (alignof 'outer))

(defun inner_offset ()
  (declare (returns usize) (c-export :c))
  (offset-of 'outer 'inner))

(defun count_offset ()
  (declare (returns usize) (c-export :c))
  (offset-of 'inner 'count))

(defun mixed_size ()
  (declare (returns usize) (c-export :c))
  (sizeof 'mixed))

(defun mixed_alignment ()
  (declare (returns usize) (c-export :c))
  (alignof 'mixed))

(defun mixed_context_offset ()
  (declare (returns usize) (c-export :c))
  (offset-of 'mixed 'context))

(defun read_inner_count (value)
  (declare (type (ptr inner) value)
           (returns c-ulong)
           (c-export :c))
  (deref (field-pointer value 'count)))
