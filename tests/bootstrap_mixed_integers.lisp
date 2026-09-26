(defun narrow_byte (value)
  (declare (type u64 value) (returns u8) (c-export :c))
  (wrap-cast u8 value))

(defun widen_signed (value)
  (declare (type s8 value) (returns s64) (c-export :c))
  (wrap-cast s64 value))

(defun signed_to_unsigned (value)
  (declare (type s32 value) (returns u64) (c-export :c))
  (wrap-cast u64 value))

(defun cast_literal ()
  (declare (returns s8) (c-export :c))
  (wrap-cast s8 128))

(defun positive_flag (value)
  (declare (type s32 value) (returns u8) (c-export :c))
  (if (< 0 value) 1 0))

(defun integer_truth ()
  (declare (returns u8) (c-export :c))
  (if (narrow_byte 256) 1 0))

(defun boolean_choice (value)
  (declare (type s32 value) (returns u8) (c-export :c))
  (let ((empty nil))
    (cond
      (empty 7)
      ((< value 0) 1)
      (t 2))))

(defun lexical_mix (value other)
  (declare (type s8 value) (type u64 other)
           (returns u64) (c-export :c))
  (let ((negative (widen_signed value))
        (byte (narrow_byte other))
        (ordered (< value 0)))
    (if ordered
        (wrap+ (wrap-cast u64 negative) (wrap-cast u64 byte))
        (wrap-cast u64 byte))))

(defun mixed_six (a b c d e f)
  (declare (type u8 a) (type s8 b) (type u16 c)
           (type s16 d) (type u32 e) (type s32 f)
           (returns s64) (c-export :c))
  (wrap+ (wrap-cast s64 a)
         (wrap+ (wrap-cast s64 b)
                (wrap+ (wrap-cast s64 c)
                       (wrap+ (wrap-cast s64 d)
                              (wrap+ (wrap-cast s64 e)
                                     (wrap-cast s64 f)))))))

(defun nested_mixed ()
  (declare (returns s64) (c-export :c))
  (mixed_six 255 -128 65535 -32768 4294967295 -2147483648))
