;; Integer representation rules shared by native source analysis and HIR
;; verification. This compiler module is also compiled directly by the native
;; bootstrap compiler; it has no parser, layout, or host-Lisp dependencies.

(defun scalar_type_signed_p (code)
  (declare (type u32 code) (returns c-int))
  (if (< 5 code) (if (< code 11) 1 0) 0))

(defun scalar_valid_code_p (code)
  (declare (type u32 code) (returns c-int))
  (if (= code 0) 0 (if (< code 11) 1 0)))

(defun scalar_binary_code_p (code shift64)
  (declare (type u32 code) (type c-int shift64) (returns c-int))
  (if (= (scalar_valid_code_p code) 0)
      0
      (if (= shift64 1) (if (= code 1) 1 0) 1)))

(defun scalar_type_bits (code)
  (declare (type u32 code) (returns u32) (c-export :c))
  (cond
    ((= code 3) 8)
    ((= code 6) 8)
    ((= code 4) 16)
    ((= code 7) 16)
    ((= code 5) 32)
    ((= code 8) 32)
    (t 64)))

(defun scalar_unsigned_limit (bits)
  (declare (type u32 bits) (returns u64))
  (cond
    ((= bits 8) 255)
    ((= bits 16) 65535)
    ((= bits 32) 4294967295)
    (t 18446744073709551615)))

(defun scalar_signed_magnitude_limit (bits negative)
  (declare (type u32 bits) (type u8 negative) (returns u64))
  (let ((minimum_magnitude
         (if (= bits 8) 128
             (if (= bits 16) 32768
                 (if (= bits 32) 2147483648 9223372036854775808)))))
    (if (= negative 1) minimum_magnitude (wrap- minimum_magnitude 1))))

(defun scalar_word_valid_p (code value)
  (declare (type u32 code) (type u64 value) (returns c-int) (c-export :c))
  (let ((bits (scalar_type_bits code)))
    (if (= (scalar_valid_code_p code) 0)
        0
        (if (= (scalar_type_signed_p code) 1)
            (if (< (scalar_signed_magnitude_limit bits 0) value)
                (if (< value (wrap- 0 (scalar_signed_magnitude_limit bits 1)))
                    0 1)
                1)
            (if (< (scalar_unsigned_limit bits) value) 0 1)))))
