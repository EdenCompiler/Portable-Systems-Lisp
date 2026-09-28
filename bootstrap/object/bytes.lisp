(include "../binary.lisp")

;; Format-independent byte copying and padding. Callers reserve the output.
(defun emit_zero_until (buffer stop)
  (declare (type (ptr byte_buffer) buffer)
           (type usize stop)
           (returns c-int))
  (while (< (deref (field-pointer buffer 'length)) stop)
    (emit_byte_unchecked buffer 0))
  1)

(defun emit_source_bytes (buffer source length)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr u8) source)
           (type usize length)
           (returns c-int))
  (let ((start (deref (field-pointer buffer 'length))))
    (while (< (deref (field-pointer buffer 'length))
              (wrap+ start length))
      (let ((index (wrap- (deref (field-pointer buffer 'length)) start)))
        (emit_byte_unchecked
         buffer (deref (pointer+ source (wrap-cast isize index)))))))
  1)
