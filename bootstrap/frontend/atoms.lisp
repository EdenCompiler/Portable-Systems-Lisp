;; Interpret integer atoms from scanner spans. The sign is recorded separately
;; so type checking can decide which machine integer types accept the value.

(defcstruct psl_parsed_integer
  (magnitude u64)
  (negative u8)
  (radix u8))

(defun integer_digit (byte)
  (declare (type u8 byte) (returns u8))
  (if (< byte 48)
      255
      (if (< byte 58)
          (wrap- byte 48)
          (if (< byte 65)
              255
              (if (< byte 71)
                  (wrap- byte 55)
                  (if (< byte 97)
                      255
                      (if (< byte 103)
                          (wrap- byte 87)
                          255)))))))

(defun integer_radix (data index end)
  (declare (type (ptr u8) data)
           (type usize index end)
           (returns u8))
  (if (< (wrap+ index 1) end)
      (if (= (deref (pointer+ data (wrap-cast isize index))) 35)
          (let ((letter (bits-and
                         (deref (pointer+ data
                                          (wrap-cast isize (wrap+ index 1))))
                         223)))
            (if (= letter 88) 16
                (if (= letter 66) 2
                    (if (= letter 79) 8
                        (if (= letter 68) 10 0)))))
          10)
      10))

(defun radix_limit (radix)
  (declare (type u8 radix) (returns u64))
  (if (= radix 2) 9223372036854775807
      (if (= radix 8) 2305843009213693951
          (if (= radix 10) 1844674407370955161
              1152921504606846975))))

(defun radix_remainder (radix)
  (declare (type u8 radix) (returns u8))
  (if (= radix 10) 5 (wrap- radix 1)))

(defun integer_overflows_p (value digit radix)
  (declare (type u64 value)
           (type u8 digit radix)
           (returns c-int))
  (let ((limit (radix_limit radix)))
    (if (< limit value)
        1
        (if (= limit value)
            (if (< (radix_remainder radix) digit) 1 0)
            0))))

(defun parse_digits (data index end radix value output)
  (declare (type (ptr u8) data)
           (type usize index end)
           (type u8 radix)
           (type u64 value)
           (type (ptr psl_parsed_integer) output)
           (returns c-int))
  (if (= index end)
      (progn (store (field-pointer output 'magnitude) value) 1)
      (let ((digit (integer_digit
                    (deref (pointer+ data (wrap-cast isize index))))))
        (if (< digit radix)
            (if (= (integer_overflows_p value digit radix) 1)
                2
                (parse_digits
                 data (wrap+ index 1) end radix
                 (wrap+ (wrap* value (wrap-cast u64 radix))
                        (wrap-cast u64 digit))
                 output))
            0))))

(defun parse_integer_body (data digits end negative output)
  (declare (type (ptr u8) data)
           (type usize digits end)
           (type u8 negative)
           (type (ptr psl_parsed_integer) output)
           (returns c-int))
  (if (= digits end)
      0
      (let ((radix (integer_radix data digits end)))
        (if (= radix 0)
            0
            (let ((begin (if (= (deref
                                  (pointer+ data (wrap-cast isize digits)))
                                 35)
                             (wrap+ digits 2)
                             digits)))
              (if (= begin end)
                  0
                  (progn
                    (store (field-pointer output 'negative) negative)
                    (store (field-pointer output 'radix) radix)
                    (parse_digits data begin end radix 0 output))))))))

(defun parse_integer_token (data start length output)
  (declare (type (ptr u8) data)
           (type usize start length)
           (type (ptr psl_parsed_integer) output)
           (returns c-int)
           (c-export :c))
  (if (= length 0)
      0
      (let ((first (deref (pointer+ data (wrap-cast isize start)))))
        (parse_integer_body
         data
         (if (= first 43)
             (wrap+ start 1)
             (if (= first 45) (wrap+ start 1) start))
         (wrap+ start length)
         (if (= first 45) 1 0)
         output))))
