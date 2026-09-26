;; Native PSL port of the compiler's little-endian byte emission primitives.
;; The caller owns the storage; later bootstrap stages can supply a growable
;; allocator without changing these encoding operations.

(defcstruct byte_buffer
  (data (ptr u8))
  (length usize)
  (capacity usize))

(defun room_for (buffer count)
  (declare (type (ptr byte_buffer) buffer)
           (type usize count)
           (returns c-int))
  (let ((used (deref (field-pointer buffer 'length)))
        (capacity (deref (field-pointer buffer 'capacity))))
    (if (< capacity used)
        0
        (if (< (wrap- capacity used) count) 0 1))))

(defun emit_byte_unchecked (buffer byte)
  (declare (type (ptr byte_buffer) buffer)
           (type u8 byte)
           (returns c-int))
  (let ((data (deref (field-pointer buffer 'data)))
        (used (deref (field-pointer buffer 'length))))
    (store (pointer+ data (wrap-cast isize used)) byte)
    (store (field-pointer buffer 'length) (wrap+ used 1))
    1))

(defun emit_byte (buffer byte)
  (declare (type (ptr byte_buffer) buffer)
           (type u8 byte)
           (returns c-int)
           (c-export :c))
  (if (= (room_for buffer 1) 1)
      (emit_byte_unchecked buffer byte)
      0))

(defun emit_integer_steps (buffer bits start stop)
  (declare (type (ptr byte_buffer) buffer)
           (type u64 bits)
           (type usize start stop)
           (returns c-int))
  (while (< (deref (field-pointer buffer 'length)) stop)
    (let ((index (wrap- (deref (field-pointer buffer 'length)) start)))
      (emit_byte_unchecked
       buffer
       (wrap-cast u8
                  (shr64 bits (wrap* (wrap-cast u64 index) 8))))))
  1)

(defun emit_integer (buffer bits count)
  (declare (type (ptr byte_buffer) buffer)
           (type u64 bits)
           (type usize count)
           (returns c-int)
           (c-export :c))
  (if (< 8 count)
      0
      (if (= (room_for buffer count) 1)
          (let ((start (deref (field-pointer buffer 'length))))
            (emit_integer_steps buffer bits start (wrap+ start count)))
          0)))

(defun patch_integer_steps (data bits remaining)
  (declare (type (ptr u8) data)
           (type u64 bits)
           (type usize remaining)
           (returns c-int))
  (if (= remaining 0)
      1
      (progn
        (store data (wrap-cast u8 bits))
        (patch_integer_steps (pointer+ data 1)
                             (shr64 bits 8)
                             (wrap- remaining 1)))))

(defun patch_i32 (buffer offset value)
  (declare (type (ptr byte_buffer) buffer)
           (type usize offset)
           (type s32 value)
           (returns c-int)
           (c-export :c))
  (let ((used (deref (field-pointer buffer 'length)))
        (data (deref (field-pointer buffer 'data))))
    (if (< used offset)
        0
        (if (< (wrap- used offset) 4)
            0
            (patch_integer_steps
             (pointer+ data (wrap-cast isize offset))
             (wrap-cast u64 value) 4)))))

(defun low_byte_bits (value)
  (declare (type u64 value)
           (returns u64)
           (c-export :c))
  (bits-and value 255))
