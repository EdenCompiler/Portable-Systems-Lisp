(include "string_decode.lisp")

;; Hosted literals own decoded source bytes. Their address is private IR data,
;; while the runtime call returns a fresh, precisely collected string.

(defun native_literal_span_p (context entry)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_data_import) entry) (returns c-int))
  (let ((base (ptr-address (deref (field-pointer context 'data_bytes))))
        (address (ptr-address (deref (field-pointer entry 'bytes))))
        (used (deref (field-pointer context 'data_byte_count)))
        (size (deref (field-pointer entry 'size))))
    (if (= base 0) 0
        (if (< (deref (field-pointer context 'data_byte_capacity)) used) 0
            (if (< address base) 0
                (let ((offset (wrap-cast usize (wrap- address base))))
                  (if (< used offset) 0
                      (if (= size 0) 0
                          (if (< (wrap- used offset) size) 0 1)))))))))

(defun native_literal_entry_p (context entry)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_data_import) entry) (returns c-int))
  (cond
    ((= (deref (field-pointer entry 'literal)) 0) 0)
    ((< 1 (deref (field-pointer entry 'literal))) 0)
    ((= (deref (field-pointer entry 'global)) 0)
     (if (= (deref (field-pointer entry 'defined)) 1)
         (if (= (deref (field-pointer entry 'type_ast)) 0)
             (if (= (deref (field-pointer entry 'alignment)) 1)
                 (native_literal_span_p context entry) 0) 0) 0))
    (t 0)))

(defun native_literal_target_p (context target)
  (declare (type (ptr native_compile_context) context)
           (type usize target) (returns c-int))
  (cond
    ((= (deref (field-pointer context 'profile)) 0) 0)
    ((< 1 (deref (field-pointer context 'profile))) 0)
    ((= (ptr-address (deref (field-pointer context 'data_imports))) 0) 0)
    ((< (deref (field-pointer context 'data_capacity))
        (deref (field-pointer context 'data_count))) 0)
    ((= target 0) 0)
    ((< (deref (field-pointer context 'data_count)) target) 0)
    (t (native_literal_entry_p context (native_data_import_at context (wrap- target 1))))))

(defun native_literal_extent_p (context target length)
  (declare (type (ptr native_compile_context) context)
           (type usize target) (type u64 length) (returns c-int))
  (if (= (native_literal_target_p context target) 0) 0
      (if (= length (wrap-cast u64
                     (wrap- (deref (field-pointer
                                    (native_data_import_at context (wrap- target 1))
                                    'size)) 1))) 1 0)))

(defun native_literal_index_from (context start index)
  (declare (type (ptr native_compile_context) context)
           (type usize start index) (returns usize))
  (if (= index (deref (field-pointer context 'data_count))) 0
      (let ((entry (native_data_import_at context index)))
        (if (= (deref (field-pointer entry 'literal)) 1)
            (if (= (deref (field-pointer entry 'initial)) (wrap-cast u64 start))
                (wrap+ index 1)
                (native_literal_index_from context start (wrap+ index 1)))
            (native_literal_index_from context start (wrap+ index 1))))))

(defun native_literal_room_p (context size)
  (declare (type (ptr native_compile_context) context)
           (type usize size) (returns c-int))
  (if (= (ptr-address (deref (field-pointer context 'data_imports))) 0) 0
      (if (= (ptr-address (deref (field-pointer context 'data_bytes))) 0) 0
          (if (< (deref (field-pointer context 'data_count))
                 (deref (field-pointer context 'data_capacity)))
              (native_c_string_room_p context size) 0))))

(defun native_literal_commit (context body size)
  (declare (type (ptr native_compile_context) context)
           (type usize body size) (returns usize))
  (let ((index (deref (field-pointer context 'data_count)))
        (byte-index (deref (field-pointer context 'data_byte_count)))
        (node (parser_node (deref (field-pointer context 'parser)) body)))
    (let ((entry (native_data_import_at context index))
          (start (deref (field-pointer node 'start)))
          (bytes (pointer+ (deref (field-pointer context 'data_bytes))
                           (wrap-cast isize byte-index))))
      (if (= (native_literal_decode context body bytes) size)
          (progn
            (store (field-pointer entry 'name) (ffi:c-string "literal"))
            (store (field-pointer entry 'name_length) 7)
            (store (field-pointer entry 'type_ast) 0)
            (store (field-pointer entry 'size) size)
            (store (field-pointer entry 'alignment) 1)
            (store (field-pointer entry 'bytes) bytes)
            (store (field-pointer entry 'initial) (wrap-cast u64 start))
            (store (field-pointer entry 'defined) 1)
            (store (field-pointer entry 'global) 0)
            (store (field-pointer entry 'referenced) 0)
            (store (field-pointer entry 'literal) 1)
            (store (field-pointer context 'data_count) (wrap+ index 1))
            (store (field-pointer context 'data_byte_count) (wrap+ byte-index size))
            (wrap+ index 1)) 0))))

(defun native_literal_data (context body)
  (declare (type (ptr native_compile_context) context)
           (type usize body) (returns usize))
  (let ((node (parser_node (deref (field-pointer context 'parser)) body)))
    (let ((existing (native_literal_index_from context (deref (field-pointer node 'start)) 0)))
      (if (< 0 existing) existing
          (let ((size (native_literal_decode context body (ptr-from-address (ptr u8) 0))))
            (if (= (native_literal_room_p context size) 0) 0
                (native_literal_commit context body size)))))))

(defun native_literal_call_hir (context body target)
  (declare (type (ptr native_compile_context) context)
           (type usize body target) (returns usize))
  (let ((arena (deref (field-pointer context 'hir)))
        (function (native_runtime_function_index context 14 0))
        (entry (native_data_import_at context (wrap- target 1))))
    (if (= function 0) 0
        (let ((address (hir_new_scalar arena 35 0 0 0 target body 1))
              (length (hir_new_scalar arena 1 (wrap-cast u64 (wrap- (deref (field-pointer entry 'size)) 1)) 0 0 0 body 2)))
          (if (= address 0) 0
              (if (= length 0) 0
                  (let ((first (hir_new_scalar arena 17 0 address 0 0 body 1)))
                    (if (= first 0) 0
                        (let ((last (hir_new_scalar arena 17 0 length first 0 body 2)))
                          (if (= last 0) 0 (hir_new_scalar arena 7 0 last 0 function body 15)))))))))))

(defun analyze_string_literal (context body)
  (declare (type (ptr native_compile_context) context)
           (type usize body) (returns usize))
  (if (= (deref (field-pointer context 'profile)) 1)
      (let ((expected (deref (field-pointer context 'expected_type))))
        (if (if (= expected 0) t (= expected 15))
            (let ((target (native_literal_data context body)))
              (if (= target 0) 0 (native_literal_call_hir context body target))) 0))
      0))
