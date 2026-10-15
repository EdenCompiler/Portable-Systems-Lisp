;; Managed primitives resolve to the checked runtime ABI catalogue.

(defun native_lambda_argument_p (context argument)
  (declare (type (ptr native_compile_context) context)
           (type usize argument) (returns c-int))
  (let ((parser (deref (field-pointer context 'parser)))
        (source (deref (field-pointer context 'source))))
    (if (= (source_type_reference_p context argument) 0) 0
      (let ((node (parser_node parser argument)))
      (if (= (deref (field-pointer node 'kind)) 8)
          (if (= (ast_variable_name_p parser source argument) 1) 1
              (let ((start (deref (field-pointer node 'start)))
                    (length (deref (field-pointer node 'length))))
                (if (if (= (deref (pointer+ source (wrap-cast isize start))) 37)
                        t nil)
                    (if (= (wrap- length 1) 0) 0
                        (if (= (source_identifier_from source
                                  (wrap+ start 1) (wrap- length 1) 0) 1)
                            1 0))
                    0)))
          0)))))

(defun native_lambda_origin_p (context origin)
  (declare (type (ptr native_compile_context) context) (type usize origin)
           (returns c-int) (c-export :c))
  (let ((parser (deref (field-pointer context 'parser))))
    (if (= (source_type_reference_p context origin) 0) 0
      (if (= (ast_list_p parser origin) 0) 0
        (let ((head (ast_first parser origin)))
          (if (= (ast_package_name_p parser head 1 (ffi:c-string "LAMBDA") 6) 0)
              0
              (let ((parameters (ast_next parser head)))
                (if (= (ast_list_p parser parameters) 0) 0
                    (let ((argument (ast_first parser parameters)))
                      (if (= (native_lambda_argument_p context argument) 0)
                          0
                          (if (= (ast_next parser argument) 0)
                          (if (= (ast_next parser parameters) 0) 0 1)
                              0)))))))))))
(defun native_managed_operator (context head)
  (declare (type (ptr native_compile_context) context) (type usize head) (returns u32))
  (let ((parser (deref (field-pointer context 'parser)))
        (source (deref (field-pointer context 'source))))
    (if (= (deref (field-pointer context 'profile)) 1)
        (cond
          ((= (ast_word_p parser source head #x736e6f63 4) 1) 1)
          ((= (ast_word_p parser source head #x726163 3) 1) 2)
          ((= (ast_word_p parser source head #x726463 3) 1) 3)
          ((= (ast_long_word_p parser source head #x6e7869662d786f62 #x6d75 10) 1) 4)
          ((= (ast_long_word_p parser source head #x69662d786f626e75 #x6d756e78 12) 1) 5)
          ((= (ast_word_p parser source head #x7165 2) 1) 9)
          ((= (ast_long_word_p parser source head #x2d7463656c6c6f63 #x65676162726167 15) 1) 6)
          ((= (ast_long_word_p parser source head #x7479622d656b616d #x676e697274732d65 16) 1) 11)
          ((= (ast_long_word_p parser source head #x622d676e69727473 #x657479 11) 1) 12)
          ((= (ast_long_word_p parser source head #x697274732d746573 #x657479622d676e 15) 1) 13)
          ((= (ast_package_name_p parser head 1 (ffi:c-string "MAKE-SYMBOL") 11) 1) 15)
          ((= (ast_package_name_p parser head 1 (ffi:c-string "SYMBOL-NAME") 11) 1) 16)
          ((= (ast_package_name_p parser head 2 (ffi:c-string "MAKE-PACKAGE-FROM-NAME") 22) 1) 17)
          ((= (ast_package_name_p parser head 1 (ffi:c-string "PACKAGE-NAME") 12) 1) 18)
          ((= (ast_package_name_p parser head 2 (ffi:c-string "INTERN-SYMBOL") 13) 1) 19)
          ((= (ast_package_name_p parser head 1 (ffi:c-string "VALUES") 6) 1) 20)
          ((= (ast_package_name_p parser head 1 (ffi:c-string "FUNCALL") 7) 1) 23)
          (t 0)) 0)))

(defun hir_from_managed_call (context body head id depth)
  (declare (type (ptr native_compile_context) context) (type usize body head depth)
           (type u32 id) (returns usize))
  (let ((index (native_runtime_function_index context id 0)))
    (if (= index 0) 0 (hir_from_resolved_call context body head index depth))))

(defun hir_managed_truth (context value body)
  (declare (type (ptr native_compile_context) context) (type usize value body) (returns usize))
  (let ((arena (deref (field-pointer context 'hir)))
        (index (native_runtime_function_index context 10 0)))
    (if (= index 0) 0
        (let ((link (hir_copy_type arena (hir_new_scalar arena 17 0 value 0 0 body 15) value)))
          (if (= link 0) 0 (hir_new_scalar arena 7 0 link 0 index body 0))))))
