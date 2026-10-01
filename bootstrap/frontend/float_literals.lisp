(include "float_decimal.lisp")

(defun float_ratio_scale (state exponent)
  (declare (type (ptr native_float_parser) state) (type s64 exponent)
           (returns c-int))
  (if (< exponent 0)
      (float_uint_power_five (field-pointer state 'denominator)
                             (wrap-cast u32 (wrap- 0 exponent)))
      (float_uint_power_five (field-pointer state 'numerator)
                             (wrap-cast u32 exponent))))

(defun float_ratio_normalize (state exponent)
  (declare (type (ptr native_float_parser) state) (type s64 exponent)
           (returns s64))
  (let ((numerator (field-pointer state 'numerator))
        (denominator (field-pointer state 'denominator)))
    (let ((shift (wrap- (wrap-cast s64 (float_uint_bits numerator))
                        (wrap-cast s64 (float_uint_bits denominator)))))
      (if (< shift 0)
          (float_uint_shift numerator (wrap-cast u32 (wrap- 0 shift)))
          (float_uint_shift denominator (wrap-cast u32 shift)))
      (if (< (float_uint_compare numerator denominator) 0)
          (progn (float_uint_shift numerator 1) (wrap- (wrap+ exponent shift) 1))
          (wrap+ exponent shift)))))

(defun float_quotient_bits (numerator denominator remaining quotient)
  (declare (type (ptr native_float_uint) numerator denominator)
           (type u32 remaining) (type u64 quotient) (returns u64))
  (if (= remaining 0) quotient
      (progn
        (float_uint_shift numerator 1)
        (let ((bit (if (< (float_uint_compare numerator denominator) 0) 0
                       (progn (float_uint_subtract numerator denominator) 1))))
          (float_quotient_bits numerator denominator (wrap- remaining 1)
                               (wrap+ (float_shift_left quotient 1) bit))))))

(defun float_round_quotient (state quotient)
  (declare (type (ptr native_float_parser) state) (type u64 quotient)
           (returns u64))
  (let ((numerator (field-pointer state 'numerator))
        (denominator (field-pointer state 'denominator)))
    (float_uint_shift numerator 1)
    (let ((comparison (float_uint_compare numerator denominator)))
      (if (< 0 comparison) (wrap+ quotient 1)
          (if (= comparison 0)
              (if (= (bits-and quotient 1) 1) (wrap+ quotient 1)
                  (if (= (deref (field-pointer state 'sticky)) 1)
                      (wrap+ quotient 1) quotient))
              quotient)))))

(defun float_sign_mask (state)
  (declare (type (ptr native_float_parser) state) (returns u64))
  (if (= (deref (field-pointer state 'negative)) 0) 0
      (if (= (deref (field-pointer state 'code)) 13) 2147483648
          9223372036854775808)))

(defun float_store_bits (state output bits)
  (declare (type (ptr native_float_parser) state)
           (type (ptr psl_parsed_integer) output) (type u64 bits)
           (returns c-int))
  (store (field-pointer output 'magnitude) (wrap+ bits (float_sign_mask state)))
  (store (field-pointer output 'negative) (deref (field-pointer state 'negative)))
  (store (field-pointer output 'radix) (wrap-cast u8 (deref (field-pointer state 'code))))
  1)

(defun float_encode_normal (state output exponent precision quotient)
  (declare (type (ptr native_float_parser) state)
           (type (ptr psl_parsed_integer) output) (type s64 exponent)
           (type u32 precision) (type u64 quotient) (returns c-int))
  (let ((bias (wrap-cast s64 (if (= precision 24) 127 1023)))
        (maximum (wrap-cast s64 (if (= precision 24) 127 1023))))
    (if (< maximum exponent) 2
        (if (= quotient (float_shift_left 1 (wrap-cast u64 precision)))
            (float_encode_normal state output (wrap+ exponent 1) precision
                                  (shr64 quotient 1))
            (float_store_bits
             state output
             (wrap+ (float_shift_left (wrap-cast u64 (wrap+ exponent bias))
                              (wrap-cast u64 (wrap- precision 1)))
                      (wrap- quotient (float_shift_left 1 (wrap-cast u64 (wrap- precision 1))))))))))

(defun float_encode_ratio (state output exponent)
  (declare (type (ptr native_float_parser) state)
           (type (ptr psl_parsed_integer) output) (type s64 exponent)
           (returns c-int))
  (let ((precision (wrap-cast u32 (if (= (deref (field-pointer state 'code)) 13) 24 53)))
        (minimum (if (= (deref (field-pointer state 'code)) 13)
                     (wrap-cast s64 -126) (wrap-cast s64 -1022)))
        (numerator (field-pointer state 'numerator))
        (denominator (field-pointer state 'denominator)))
    (let ((minimum_bit (wrap- minimum (wrap-cast s64 (wrap- precision 1)))))
      (cond
        ((< exponent (wrap- minimum_bit 1)) (float_store_bits state output 0))
        ((= exponent (wrap- minimum_bit 1))
         (float_store_bits state output
                          (if (= (float_uint_compare numerator denominator) 0)
                              (if (= (deref (field-pointer state 'sticky)) 1) 1 0)
                              1)))
        (t
         (let ((bits (if (< exponent minimum)
                         (wrap-cast u32 (wrap+ (wrap- exponent minimum_bit) 1))
                         precision)))
           (float_uint_subtract numerator denominator)
           (let ((quotient (float_round_quotient
                            state (float_quotient_bits numerator denominator
                                                       (wrap- bits 1) 1))))
             (if (< exponent minimum) (float_store_bits state output quotient)
                 (float_encode_normal state output exponent precision quotient)))))))))

(defun float_convert_decimal (state output)
  (declare (type (ptr native_float_parser) state)
           (type (ptr psl_parsed_integer) output) (returns c-int))
  (if (= (deref (field-pointer state 'digits)) 0) (float_store_bits state output 0)
      (let ((exponent (float_decimal_exponent state)))
        (let ((order (wrap+ exponent
                            (wrap-cast s64 (deref (field-pointer state 'digits))))))
          (if (< order (wrap-cast s64 -350)) (float_store_bits state output 0)
              (if (< 310 order) 2
                  (if (= (float_ratio_scale state exponent) 0) 2
                      (float_encode_ratio state output
                                           (float_ratio_normalize state exponent)))))))))

;; 1: valid float with IEEE payload in output.magnitude; 0: not a float;
;; 2: finite decimal outside the representable range or insufficient scratch.
(defun parse_float_token (data start length state numerator denominator capacity output)
  (declare (type (ptr u8) data) (type usize start length capacity)
           (type (ptr native_float_parser) state)
           (type (ptr u32) numerator denominator)
           (type (ptr psl_parsed_integer) output)
           (returns c-int) (c-export :c))
  (if (< (wrap+ start length) start) 2
      (if (< 1152921504606846975 (wrap-cast u64 (wrap+ start length))) 2
  (if (= length 0) 0
      (if (< capacity 128) 2
          (progn
            (float_parser_initialize state numerator denominator capacity)
            (let ((first (deref (pointer+ data (wrap-cast isize start)))))
              (store (field-pointer state 'negative) (if (= first 45) 1 0))
              (let ((begin (if (= first 43) (wrap+ start 1)
                               (if (= first 45) (wrap+ start 1) start))))
                (if (= (float_parse_mantissa state data begin (wrap+ start length)) 0) 0
                    (float_convert_decimal state output))))))))))
