(include "float_literals.lisp")

(defun scalar_float_type_code (layouts type)
  (declare (type (ptr native_layout_context) layouts) (type usize type)
           (returns u32))
  (cond
    ((= (layout_word_p layouts type #x323366 3) 1) 13)
    ((= (layout_type_word_p layouts type #x74616f6c662d63 0 7) 1) 13)
    ((= (layout_word_p layouts type #x343666 3) 1) 14)
    ((= (layout_type_word_p layouts type #x656c62756f642d63 0 8) 1) 14)
    (t 0)))

(defun source_word_valid_p (code value)
  (declare (type u32 code) (type u64 value) (returns c-int))
  (if (= code 13) (if (< 4294967295 value) 0 1)
      (if (= code 14) 1 (scalar_word_valid_p code value))))

(defun scalar_float_atom_scratch (context body start)
  (declare (type (ptr native_compile_context) context) (type usize body start)
           (returns c-int))
  (let ((state (ptr-cast (ptr native_float_parser)
                         (pointer+ (deref (field-pointer context 'data_bytes))
                                   (wrap-cast isize start))))
        (node (parser_node (deref (field-pointer context 'parser)) body)))
    (let ((words (ptr-cast (ptr u32)
                           (pointer+ (ptr-cast (ptr u8) state)
                                     (wrap-cast isize (sizeof 'native_float_parser))))))
      (parse_float_token
       (deref (field-pointer context 'source))
       (deref (field-pointer node 'start)) (deref (field-pointer node 'length))
       state words (pointer+ words 128) 128
       (deref (field-pointer context 'integer))))))

(defun scalar_float_atom_p (context body)
  (declare (type (ptr native_compile_context) context) (type usize body)
           (returns c-int))
  (let ((count (deref (field-pointer context 'data_byte_count)))
        (capacity (deref (field-pointer context 'data_byte_capacity)))
        (base (deref (field-pointer context 'data_bytes))))
    (if (< capacity count) 2
        (if (= (ptr-address base) 0) 2
            (let ((padding (bits-and (wrap- 0 (wrap+ (ptr-address base) count))
                                      (wrap- (alignof 'native_float_parser) 1)))
                  (needed (wrap+ (sizeof 'native_float_parser)
                                (wrap* 256 (sizeof 'u32)))))
              (if (< (wrap- capacity count) padding) 2
                  (if (< (wrap- (wrap- capacity count) padding) needed) 2
                      (scalar_float_atom_scratch context body (wrap+ count padding)))))))))

(defun hir_from_float_literal (context body)
  (declare (type (ptr native_compile_context) context) (type usize body)
           (returns usize))
  (let ((integer (deref (field-pointer context 'integer)))
        (expected (deref (field-pointer context 'expected_type))))
    (let ((code (wrap-cast u32 (deref (field-pointer integer 'radix)))))
      (if (= expected 0)
          (hir_new_scalar (deref (field-pointer context 'hir)) 1
                          (deref (field-pointer integer 'magnitude)) 0 0 0 body code)
          (if (= expected code)
              (hir_new_scalar (deref (field-pointer context 'hir)) 1
                              (deref (field-pointer integer 'magnitude)) 0 0 0 body code)
              0)))))
