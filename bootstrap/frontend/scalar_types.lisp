;; Source integer types for the native integer subset. HIR values
;; use a 64-bit word; each node retains its source type for extension, wrapping,
;; literal ranges, and comparison signedness.

(include "../ir/integer_types.lisp")

(defun scalar_type_code (signatures type)
  (declare (type (ptr native_signature_context) signatures)
           (type usize type)
           (returns u32))
  (cond
    ((= (signature_word_p signatures type #x343675 3) 1) 1) ; u64
    ((= (signature_word_p signatures type #x657a697375 5) 1) 2) ; usize
    ((= (signature_word_p signatures type #x3875 2) 1) 3) ; u8
    ((= (signature_word_p signatures type #x363175 3) 1) 4) ; u16
    ((= (signature_word_p signatures type #x323375 3) 1) 5) ; u32
    ((= (signature_word_p signatures type #x3873 2) 1) 6) ; s8
    ((= (signature_word_p signatures type #x363173 3) 1) 7) ; s16
    ((= (signature_word_p signatures type #x323373 3) 1) 8) ; s32
    ((= (signature_word_p signatures type #x746e692d63 5) 1) 8) ; c-int
    ((= (signature_word_p signatures type #x343673 3) 1) 9) ; s64
    ((= (signature_word_p signatures type #x657a697369 5) 1) 10) ; isize
    (t (if (= (source_type_pointee signatures type) 0) 0 11))))

(defun scalar_literal_code (expected integer)
  (declare (type u32 expected)
           (type (ptr psl_parsed_integer) integer)
           (returns u32))
  (if (= expected 0)
      (if (= (deref (field-pointer integer 'negative)) 1)
          (if (= (deref (field-pointer integer 'magnitude)) 0) 1 9)
          1)
      expected))

(defun scalar_literal_valid_p (code integer)
  (declare (type u32 code)
           (type (ptr psl_parsed_integer) integer)
           (returns c-int))
  (let ((negative (deref (field-pointer integer 'negative)))
        (magnitude (deref (field-pointer integer 'magnitude)))
        (bits (scalar_type_bits code)))
    (if (= (scalar_valid_code_p code) 0)
        0
        (if (= (scalar_type_signed_p code) 1)
        (if (< (scalar_signed_magnitude_limit bits negative) magnitude) 0 1)
        (if (= negative 1)
            (if (= magnitude 0) 1 0)
            (if (< (scalar_unsigned_limit bits) magnitude) 0 1))))))

(defun scalar_literal_bits (integer)
  (declare (type (ptr psl_parsed_integer) integer) (returns u64))
  (let ((magnitude (deref (field-pointer integer 'magnitude))))
    (if (= (deref (field-pointer integer 'negative)) 1)
        (wrap- 0 magnitude)
        magnitude)))

(defun scalar_signature_parameter_code (context signature index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize index)
           (returns u32))
  (let ((signatures (deref (field-pointer context 'signatures))))
    (let ((parameter
           (native_parameter_at
            signatures (wrap+ (deref (field-pointer signature 'first_parameter))
                               index))))
      (scalar_type_code signatures
                        (deref (field-pointer parameter 'type_ast))))))

(defun scalar_current_parameter_code (context index)
  (declare (type (ptr native_compile_context) context)
           (type usize index)
           (returns u32))
  (scalar_signature_parameter_code
   context (deref (field-pointer context 'current_signature))
   (wrap- index 1)))

(defun scalar_signature_type_code (context signature)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (returns u32))
  (scalar_type_code (deref (field-pointer context 'signatures))
                    (deref (field-pointer signature 'result_type))))

(defun scalar_parameter_p (context parameter)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_parameter) parameter)
           (returns c-int))
  (if (= (ast_variable_name_p
          (deref (field-pointer context 'parser))
          (deref (field-pointer context 'source))
          (deref (field-pointer parameter 'name))) 0)
      0
      (source_valid_code_p
       (scalar_type_code (deref (field-pointer context 'signatures))
                         (deref (field-pointer parameter 'type_ast))))))

(defun scalar_parameter_types_p (context signature index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (type usize index)
           (returns c-int))
  (if (= index (deref (field-pointer signature 'arity)))
      1
      (let ((signatures (deref (field-pointer context 'signatures))))
        (let ((parameter (native_parameter_at
                          signatures
                          (wrap+ (deref (field-pointer signature
                                                      'first_parameter))
                                 index))))
          (if (= (scalar_parameter_p context parameter) 1)
              (scalar_parameter_types_p context signature
                                        (wrap+ index 1))
              0)))))

(defun scalar_signature_p (context signature)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_signature) signature)
           (returns c-int))
  (let ((code (scalar_signature_type_code context signature)))
    (if (= code 0)
        0
        (scalar_parameter_types_p context signature 0))))
