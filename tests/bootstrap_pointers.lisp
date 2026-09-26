(defcstruct memory_pair
  (tag u8)
  (value s32)
  (data (ptr u16)))

(defcstruct memory_outer
  (first u64)
  (pair memory_pair))

(defun pointer_identity (data)
  (declare (type (ptr u16) data) (returns (ptr u16)))
  (let ((copy data))
    (if t copy data)))

(defun pointer_choose (data)
  (declare (type (ptr u16) data) (returns (ptr u16)) (c-export :c))
  (cond (nil (pointer+ data 1))
        (t (progn 0 (pointer_identity data)))))

(defun pointer_offset (data offset)
  (declare (type (ptr u16) data) (type isize offset)
           (returns (ptr u16)) (c-export :c))
  (pointer+ (pointer_identity data) offset))

(defun pointer_read8 (data)
  (declare (type (ptr s8) data) (returns s64) (c-export :c))
  (wrap-cast s64 (deref data)))

(defun pointer_read16 (data)
  (declare (type (ptr s16) data) (returns s64) (c-export :c))
  (wrap-cast s64 (deref data)))

(defun pointer_read32 (data)
  (declare (type (ptr s32) data) (returns s64) (c-export :c))
  (wrap-cast s64 (deref data)))

(defun pointer_read64 (data)
  (declare (type (ptr s64) data) (returns s64) (c-export :c))
  (deref data))

(defun pointer_write8 (data value)
  (declare (type (ptr u8) data) (type u8 value)
           (returns u8) (c-export :c))
  (store data value))

(defun pointer_write16 (data value)
  (declare (type (ptr u16) data) (type u16 value)
           (returns u16) (c-export :c))
  (store data value))

(defun pointer_write32 (data value)
  (declare (type (ptr u32) data) (type u32 value)
           (returns u32) (c-export :c))
  (store data value))

(defun pointer_write64 (data value)
  (declare (type (ptr u64) data) (type u64 value)
           (returns u64) (c-export :c))
  (store data value))

(defun pointer_chain (slot data)
  (declare (type (ptr (ptr u16)) slot) (type (ptr u16) data)
           (returns (ptr u16)) (c-export :c))
  (store slot (pointer_identity data))
  (deref slot))

(defun pointer_nested (outer value data)
  (declare (type (ptr memory_outer) outer)
           (type s32 value) (type (ptr u16) data)
           (returns u16) (c-export :c))
  (let ((pair (field-pointer outer 'pair)))
    (store (field-pointer pair (quote value)) value)
    (store (field-pointer pair 'data) data)
    (deref (pointer+ (deref (field-pointer pair 'data)) 1))))

(defun pointer_cast_byte (data)
  (declare (type (ptr u16) data) (returns u8) (c-export :c))
  (deref (ptr-cast (ptr u8) data)))

(defun pointer_null_truth ()
  (declare (returns c-int) (c-export :c))
  (if (ptr-from-address (ptr u8) 0) 1 0))

(defun pointer_from_bits (address)
  (declare (type usize address) (returns (ptr u16)) (c-export :c))
  (ptr-from-address (ptr u16) address))

(defun pointer_loop (counter limit)
  (declare (type (ptr u32) counter) (type u32 limit)
           (returns u32) (c-export :c))
  (let ((done (while (< (deref counter) limit)
                (store counter (wrap+ (deref counter) 1))
                (progn nil t))))
    (if done 999 (deref counter))))

(defun pointer_store_order (counter)
  (declare (type (ptr u32) counter) (returns u32) (c-export :c))
  (store (progn (store counter 10) counter)
         (wrap+ (deref counter) 1)))

(defun pointer_unsigned8 (data)
  (declare (type (ptr u8) data) (returns u64) (c-export :c))
  (wrap-cast u64 (deref data)))

(defun pointer_unsigned16 (data)
  (declare (type (ptr u16) data) (returns u64) (c-export :c))
  (wrap-cast u64 (deref data)))

(defun pointer_unsigned32 (data)
  (declare (type (ptr u32) data) (returns u64) (c-export :c))
  (wrap-cast u64 (deref data)))

(defun pointer_unsigned64 (data)
  (declare (type (ptr u64) data) (returns u64) (c-export :c))
  (wrap-cast u64 (deref data)))

(defun pointer_struct_stride (pairs offset)
  (declare (type (ptr memory_pair) pairs) (type isize offset)
           (returns s32) (c-export :c))
  (deref (field-pointer (pointer+ pairs offset) 'value)))
