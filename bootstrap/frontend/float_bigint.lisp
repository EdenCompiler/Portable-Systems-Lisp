;; Bounded unsigned arithmetic for decimal-to-IEEE literal conversion.
;; The caller owns the words; conversion does not allocate or call a runtime.
(defcstruct native_float_uint
  (words (ptr u32))
  (count usize)
  (capacity usize))

(defun float_uint_word (value index)
  (declare (type (ptr native_float_uint) value) (type usize index)
           (returns (ptr u32)))
  (pointer+ (deref (field-pointer value 'words)) (wrap-cast isize index)))

(defun float_uint_initialize (value words capacity initial)
  (declare (type (ptr native_float_uint) value) (type (ptr u32) words)
           (type usize capacity) (type u32 initial) (returns c-int))
  (store (field-pointer value 'words) words)
  (store (field-pointer value 'capacity) capacity)
  (store (field-pointer value 'count) 1)
  (store words initial)
  1)

(defun float_uint_finish_carry (value count carry)
  (declare (type (ptr native_float_uint) value) (type usize count)
           (type u64 carry) (returns c-int))
  (if (= carry 0) 1
      (if (= count (deref (field-pointer value 'capacity))) 0
          (progn
            (store (float_uint_word value count) (wrap-cast u32 carry))
            (store (field-pointer value 'count) (wrap+ count 1))
            1))))

(defun float_uint_multiply_from (value factor index count carry)
  (declare (type (ptr native_float_uint) value)
           (type u32 factor) (type usize index count)
           (type u64 carry) (returns c-int))
  (if (= index count) (float_uint_finish_carry value count carry)
      (let ((product (wrap+ (wrap* (wrap-cast u64 (deref (float_uint_word value index)))
                                  (wrap-cast u64 factor)) carry)))
        (store (float_uint_word value index) (wrap-cast u32 product))
        (float_uint_multiply_from value factor (wrap+ index 1) count
                                  (shr64 product 32)))))

(defun float_uint_multiply_add (value factor addend)
  (declare (type (ptr native_float_uint) value) (type u32 factor addend)
           (returns c-int))
  (float_uint_multiply_from value factor 0
                            (deref (field-pointer value 'count))
                            (wrap-cast u64 addend)))

(defun float_uint_power_five (value exponent)
  (declare (type (ptr native_float_uint) value) (type u32 exponent)
           (returns c-int))
  (if (= exponent 0) 1
      (if (= (float_uint_multiply_add value 5 0) 0) 0
          (float_uint_power_five value (wrap- exponent 1)))))

(defun float_uint_shift (value bits)
  (declare (type (ptr native_float_uint) value) (type u32 bits)
           (returns c-int))
  (if (= bits 0) 1
      (if (= (float_uint_multiply_add value 2 0) 0) 0
          (float_uint_shift value (wrap- bits 1)))))

(defun float_uint_compare_from (left right count)
  (declare (type (ptr native_float_uint) left right) (type usize count)
           (returns c-int))
  (if (= count 0) 0
      (let ((index (wrap- count 1)))
        (let ((a (deref (float_uint_word left index)))
              (b (deref (float_uint_word right index))))
          (if (< a b) (wrap-cast c-int -1)
              (if (< b a) 1 (float_uint_compare_from left right index)))))))

(defun float_uint_compare (left right)
  (declare (type (ptr native_float_uint) left right) (returns c-int))
  (let ((a (deref (field-pointer left 'count)))
        (b (deref (field-pointer right 'count))))
    (if (< a b) (wrap-cast c-int -1)
        (if (< b a) 1 (float_uint_compare_from left right a)))))

(defun float_uint_trim (value count)
  (declare (type (ptr native_float_uint) value) (type usize count)
           (returns c-int))
  (if (= count 1) (progn (store (field-pointer value 'count) count) 1)
      (if (= (deref (float_uint_word value (wrap- count 1))) 0)
          (float_uint_trim value (wrap- count 1))
          (progn (store (field-pointer value 'count) count) 1))))

(defun float_uint_subtract_from (left right index count borrow)
  (declare (type (ptr native_float_uint) left right)
           (type usize index count) (type u64 borrow) (returns c-int))
  (if (= index count) (float_uint_trim left count)
      (let ((a (wrap-cast u64 (deref (float_uint_word left index))))
            (b (if (< index (deref (field-pointer right 'count)))
                   (wrap-cast u64 (deref (float_uint_word right index))) 0)))
        (let ((subtrahend (wrap+ b borrow)))
          (store (float_uint_word left index) (wrap-cast u32 (wrap- a subtrahend)))
          (float_uint_subtract_from left right (wrap+ index 1) count
                                    (if (< a subtrahend) 1 0))))))

(defun float_uint_subtract (left right)
  (declare (type (ptr native_float_uint) left right) (returns c-int))
  (float_uint_subtract_from left right 0 (deref (field-pointer left 'count)) 0))

(defun float_word_bits (value bits)
  (declare (type u64 value) (type u32 bits) (returns u32))
  (if (= value 0) bits (float_word_bits (shr64 value 1) (wrap+ bits 1))))

(defun float_uint_bits (value)
  (declare (type (ptr native_float_uint) value) (returns u32))
  (let ((last (wrap- (deref (field-pointer value 'count)) 1)))
    (wrap+ (wrap* (wrap-cast u32 last) 32)
           (float_word_bits (wrap-cast u64 (deref (float_uint_word value last))) 0))))

(defun float_shift_left (value count)
  (declare (type u64 value count) (returns u64))
  (if (= count 0) value (float_shift_left (wrap* value 2) (wrap- count 1))))
