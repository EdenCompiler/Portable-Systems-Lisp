;; Name and operator resolution for native scalar HIR analysis.

(defun scalar_integer_atom_p (parser source body integer)
  (declare (type (ptr psl_parser) parser)
           (type (ptr u8) source)
           (type usize body)
           (type (ptr psl_parsed_integer) integer)
           (returns c-int))
  (let ((node (parser_node parser body)))
    (if (= (deref (field-pointer node 'kind)) 8)
        (parse_integer_token source (deref (field-pointer node 'start))
                             (deref (field-pointer node 'length)) integer)
        0)))

(defun binary_operation (parser source reference)
  (declare (type (ptr psl_parser) parser)
           (type (ptr u8) source)
           (type usize reference)
           (returns u8))
  (if (= (ast_word_p parser source reference #x2b70617277 5) 1)
      43 ; wrap+
      (if (= (ast_word_p parser source reference #x2d70617277 5) 1)
          45 ; wrap-
          (if (= (ast_word_p parser source reference #x2a70617277 5) 1)
              42 ; wrap*
              (if (= (ast_word_p parser source reference
                                  #x646e612d73746962 8) 1)
                  38 ; bits-and
                  (if (= (ast_word_p parser source reference
                                      #x3436726873 5) 1)
                      94 ; shr64
                      0))))))

(defun binary_parts_p (parser reference)
  (declare (type (ptr psl_parser) parser)
           (type usize reference)
           (returns c-int))
  (let ((head (ast_first parser reference)))
    (let ((left (ast_next parser head)))
      (let ((right (ast_next parser left)))
        (if (= left 0)
            0
            (if (= right 0)
                0
                (if (= (ast_next parser right) 0) 1 0)))))))

(defun parameter_index_from (context body index)
  (declare (type (ptr native_compile_context) context)
           (type usize body index)
           (returns usize))
  (if (= index (deref (field-pointer context 'current_arity)))
      0
      (let ((parser (deref (field-pointer context 'parser)))
            (source (deref (field-pointer context 'source)))
            (signatures (deref (field-pointer context 'signatures)))
            (signature (deref (field-pointer context 'current_signature))))
        (let ((parameter (native_parameter_at
                          signatures
                          (wrap+ (deref (field-pointer signature
                                                      'first_parameter))
                                 index))))
          (if (= (ast_same_name_p
                  parser source body
                  (deref (field-pointer parameter 'name))) 1)
              (wrap+ index 1)
              (parameter_index_from context body (wrap+ index 1)))))))

(defun parameter_index (context body)
  (declare (type (ptr native_compile_context) context)
           (type usize body)
           (returns usize))
  (parameter_index_from context body 0))

(defun ast_name_matches_function_p (parser source name function)
  (declare (type (ptr psl_parser) parser)
           (type (ptr u8) source)
           (type usize name)
           (type (ptr native_function) function)
           (returns c-int))
  (let ((node (parser_node parser name)))
    (let ((length (deref (field-pointer node 'length))))
      (if (= (deref (field-pointer node 'kind)) 8)
          (if (= length (deref (field-pointer function 'name_length)))
              (same_name_bytes_p
               (pointer+ source
                         (wrap-cast isize
                                    (deref (field-pointer node 'start))))
               (deref (field-pointer function 'name)) length)
              0)
          0))))

(defun prior_function_index (context name index)
  (declare (type (ptr native_compile_context) context)
           (type usize name index)
           (returns usize))
  (if (= index 0)
      0
      (let ((parser (deref (field-pointer context 'parser)))
            (source (deref (field-pointer context 'source)))
            (functions (deref (field-pointer context 'functions))))
        (if (= (ast_name_matches_function_p
                parser source name
                (native_function_at functions (wrap- index 1))) 1)
            index
            (prior_function_index context name (wrap- index 1))))))

(defun call_shape_from_p (parser argument remaining)
  (declare (type (ptr psl_parser) parser)
           (type usize argument remaining)
           (returns c-int))
  (if (= remaining 0)
      (if (= argument 0) 1 0)
      (if (= argument 0)
          0
          (call_shape_from_p parser (ast_next parser argument)
                             (wrap- remaining 1)))))

(defun call_shape_p (parser name arity)
  (declare (type (ptr psl_parser) parser)
           (type usize name arity)
           (returns c-int))
  (call_shape_from_p parser (ast_next parser name) arity))
