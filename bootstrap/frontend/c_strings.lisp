;; Explicit NUL-terminated byte strings for C calls. Ordinary source strings
;; retain their Lisp meaning; this form is only valid where (ptr u8) is expected.

(defun native_c_string_form_p (parser source head)
  (declare (type (ptr psl_parser) parser) (type (ptr u8) source)
           (type usize head) (returns c-int))
  (ast_long_word_p parser source head #x74732d633a696666 #x676e6972 12))

(defun native_c_string_expected_p (context)
  (declare (type (ptr native_compile_context) context) (returns c-int))
  (if (= (deref (field-pointer context 'expected_type)) 11)
      (if (= (scalar_type_code
              (deref (field-pointer context 'signatures))
              (deref (field-pointer context 'expected_pointee))) 3) 1 0)
      0))

(defun native_c_string_size (context string)
  (declare (type (ptr native_compile_context) context)
           (type usize string) (returns usize))
  (let ((node (parser_node (deref (field-pointer context 'parser)) string)))
    (if (= (deref (field-pointer node 'kind)) 7)
        (let ((start (deref (field-pointer node 'start))))
          (wrap+ (source_string_decoded_size
                  (deref (field-pointer context 'source)) (wrap+ start 1)
                  (wrap- (wrap+ start (deref (field-pointer node 'length))) 1)
                  0) 1))
        0)))

(defun native_c_string_room_p (context size)
  (declare (type (ptr native_compile_context) context)
           (type usize size) (returns c-int))
  (if (= size 0) 0
      (if (= (deref (field-pointer context 'data_count))
             (deref (field-pointer context 'data_capacity))) 0
          (let ((used (deref (field-pointer context 'data_byte_count)))
                (capacity (deref (field-pointer context 'data_byte_capacity))))
            (if (< capacity used) 0
                (if (< (wrap- capacity used) size) 0 1))))))

(defun native_c_string_index_from (context name index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr u8) name) (type usize index) (returns usize))
  (if (= index (deref (field-pointer context 'data_count))) 0
      (let ((entry (native_data_import_at context index)))
        (if (= (deref (field-pointer entry 'global)) 0)
            (if (= (ptr-address (deref (field-pointer entry 'name)))
                   (ptr-address name))
                (wrap+ index 1)
                (native_c_string_index_from context name (wrap+ index 1)))
            (native_c_string_index_from context name (wrap+ index 1))))))

(defun native_c_string_index (context head)
  (declare (type (ptr native_compile_context) context)
           (type usize head) (returns usize))
  (let ((node (parser_node (deref (field-pointer context 'parser)) head)))
    (native_c_string_index_from
     context
     (pointer+ (deref (field-pointer context 'source))
               (wrap-cast isize (deref (field-pointer node 'start))))
     0)))

(defun native_c_string_hir (context body target)
  (declare (type (ptr native_compile_context) context)
           (type usize body target) (returns usize))
  (hir_with_pointee
   (deref (field-pointer context 'hir))
   (hir_new_scalar (deref (field-pointer context 'hir))
                   34 0 0 0 target body 11)
   (deref (field-pointer context 'expected_pointee))))

(defun native_copy_c_string (context string output)
  (declare (type (ptr native_compile_context) context)
           (type usize string) (type (ptr u8) output) (returns c-int))
  (let ((node (parser_node (deref (field-pointer context 'parser)) string)))
    (let ((start (deref (field-pointer node 'start))))
      (source_string_copy
       (deref (field-pointer context 'source)) (wrap+ start 1)
       (wrap- (wrap+ start (deref (field-pointer node 'length))) 1)
       output 0))))

(defun native_commit_c_string (context body head string size)
  (declare (type (ptr native_compile_context) context)
           (type usize body head string size) (returns usize))
  (let ((index (deref (field-pointer context 'data_count)))
        (byte-index (deref (field-pointer context 'data_byte_count)))
        (parser (deref (field-pointer context 'parser)))
        (source (deref (field-pointer context 'source))))
    (let ((entry (native_data_import_at context index))
          (name-node (parser_node parser head))
          (bytes (pointer+ (deref (field-pointer context 'data_bytes))
                           (wrap-cast isize byte-index))))
      (if (= (native_copy_c_string context string bytes) 0) 0
          (progn
            (store (field-pointer entry 'name)
                   (pointer+ source (wrap-cast isize
                                               (deref (field-pointer name-node 'start)))))
            (store (field-pointer entry 'name_length)
                   (deref (field-pointer name-node 'length)))
            (store (field-pointer entry 'type_ast)
                   (deref (field-pointer context 'expected_pointee)))
            (store (field-pointer entry 'size) size)
            (store (field-pointer entry 'alignment) 1)
            (store (field-pointer entry 'bytes) bytes)
            (store (field-pointer entry 'initial) 0)
            (store (field-pointer entry 'defined) 1)
            (store (field-pointer entry 'global) 0)
            (store (field-pointer entry 'referenced) 0)
            (store (field-pointer context 'data_count) (wrap+ index 1))
            (store (field-pointer context 'data_byte_count)
                   (wrap+ byte-index size))
            (native_c_string_hir context body (wrap+ index 1)))))))

(defun analyze_c_string (context body head)
  (declare (type (ptr native_compile_context) context)
           (type usize body head) (returns usize))
  (let ((parser (deref (field-pointer context 'parser))))
    (let ((string (ast_next parser head)))
      (if (= (call_shape_from_p parser string 1) 0) 0
          (if (= (native_c_string_expected_p context) 0) 0
              (let ((existing (native_c_string_index context head)))
                (if (< 0 existing)
                    (native_c_string_hir context body existing)
                    (let ((size (native_c_string_size context string)))
                      (if (= (native_c_string_room_p context size) 0) 0
                          (native_commit_c_string
                           context body head string size))))))))))
