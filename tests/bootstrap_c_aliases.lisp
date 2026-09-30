(defcstruct alias_layout
  (byte c-char) (short c-ushort) (integer c-int) (long c-long)
  (size c-size-t) (difference c-ptrdiff-t) (wide c-ulong-long)
  (single c-float) (double c-double))

(ffi:import-function "alias_c_long" ((value c-long)) -> c-long)
(ffi:export-data "alias_export" c-ulong 42)

(defun alias_signed (byte short integer long wide difference)
  (declare (type c-char byte) (type c-short short) (type c-int integer)
           (type c-long long) (type c-long-long wide) (type c-ptrdiff-t difference)
           (returns s64) (c-export :c))
  (wrap+ (wrap+ (wrap-cast s64 byte) (wrap-cast s64 short))
         (wrap+ (wrap+ (wrap-cast s64 integer) (wrap-cast s64 long))
                (wrap+ wide (wrap-cast s64 difference)))))

(defun alias_unsigned (byte short integer long wide size)
  (declare (type c-uchar byte) (type c-ushort short) (type c-uint integer)
           (type c-ulong long) (type c-ulong-long wide) (type c-size-t size)
           (returns u64) (c-export :c))
  (wrap+ (wrap+ (wrap-cast u64 byte) (wrap-cast u64 short))
         (wrap+ (wrap+ (wrap-cast u64 integer) (wrap-cast u64 long))
                (wrap+ wide (wrap-cast u64 size)))))

(defun alias_call (value)
  (declare (type c-long value) (returns c-long) (c-export :c))
  (ffi:call alias_c_long value))

(defun alias_memory (pointer value)
  (declare (type (ptr c-long) pointer) (type c-long value)
           (returns c-long) (c-export :c))
  (store pointer value)
  (deref pointer))

(defun alias_long_size ()
  (declare (returns usize) (c-export :c))
  (sizeof 'c-long))

(defun alias_layout_size ()
  (declare (returns usize) (c-export :c))
  (sizeof 'alias_layout))

(defun alias_layout_alignment ()
  (declare (returns usize) (c-export :c))
  (alignof 'alias_layout))

(defun alias_long_offset ()
  (declare (returns usize) (c-export :c))
  (offset-of 'alias_layout 'long))

(defun alias_double_offset ()
  (declare (returns usize) (c-export :c))
  (offset-of 'alias_layout 'double))
