(include "layout.lisp")

;; Signature records keep parser references and resolved ABI shapes in
;; caller-owned tables. Bodies are analyzed only after all signatures exist.
(defcstruct native_parameter
  (name usize)
  (type_ast usize)
  (size usize)
  (kind u32))

(defcstruct native_signature
  (name usize)
  (first_parameter usize)
  (arity usize)
  (result_type usize)
  (result_size usize)
  (result_kind u32)
  (body usize)
  (exported u8))

(defcstruct native_signature_context
  (layouts (ptr native_layout_context))
  (signatures (ptr native_signature))
  (signature_count usize)
  (signature_capacity usize)
  (parameters (ptr native_parameter))
  (parameter_count usize)
  (parameter_capacity usize)
  (error u32))

(defun signature_parser (context)
  (declare (type (ptr native_signature_context) context)
           (returns (ptr psl_parser)))
  (deref (field-pointer (deref (field-pointer context 'layouts)) 'parser)))

(defun signature_next (context reference)
  (declare (type (ptr native_signature_context) context)
           (type usize reference)
           (returns usize))
  (if (= reference 0)
      0
      (deref (field-pointer
              (parser_node (signature_parser context) reference) 'next))))

(defun signature_first (context reference)
  (declare (type (ptr native_signature_context) context)
           (type usize reference)
           (returns usize))
  (if (= reference 0)
      0
      (deref (field-pointer
              (parser_node (signature_parser context) reference) 'first))))

(defun signature_list_p (context reference)
  (declare (type (ptr native_signature_context) context)
           (type usize reference)
           (returns c-int))
  (if (= reference 0)
      0
      (if (= (deref (field-pointer
              (parser_node (signature_parser context) reference) 'kind)) 1)
          1 0)))

(defun signature_word_p (context reference bits length)
  (declare (type (ptr native_signature_context) context)
           (type usize reference length)
           (type u64 bits)
           (returns c-int))
  (layout_word_p (deref (field-pointer context 'layouts))
                 reference bits length))

(defun native_signature_form_p (context root)
  (declare (type (ptr native_signature_context) context)
           (type usize root)
           (returns c-int)
           (c-export :c))
  (if (= (signature_list_p context root) 0)
      0
      (signature_word_p context (signature_first context root)
                        #x6e75666564 5)))

(defun native_signature_at (context index)
  (declare (type (ptr native_signature_context) context)
           (type usize index)
           (returns (ptr native_signature)))
  (pointer+ (deref (field-pointer context 'signatures))
            (wrap-cast isize index)))

(defun native_parameter_at (context index)
  (declare (type (ptr native_signature_context) context)
           (type usize index)
           (returns (ptr native_parameter)))
  (pointer+ (deref (field-pointer context 'parameters))
            (wrap-cast isize index)))

(defun signature_names_equal_p (context left right)
  (declare (type (ptr native_signature_context) context)
           (type usize left right)
           (returns c-int))
  (layout_names_equal_p (deref (field-pointer context 'layouts))
                        left right))

(defun signature_name_used_p (context name index)
  (declare (type (ptr native_signature_context) context)
           (type usize name index)
           (returns c-int))
  (if (= index (deref (field-pointer context 'signature_count)))
      0
      (if (= (signature_names_equal_p
              context name
              (deref (field-pointer (native_signature_at context index)
                                    'name))) 1)
          1
          (signature_name_used_p context name (wrap+ index 1)))))

(defun signature_parameter_index (context signature name index)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize name index)
           (returns usize))
  (if (= index (deref (field-pointer signature 'arity)))
      0
      (let ((position (wrap+ (deref (field-pointer signature
                                                   'first_parameter)) index)))
        (if (= (signature_names_equal_p
                context name
                (deref (field-pointer (native_parameter_at context position)
                                      'name))) 1)
            (wrap+ position 1)
            (signature_parameter_index context signature name
                                       (wrap+ index 1))))))

(defun signature_add_parameter (context signature name)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize name)
           (returns c-int))
  (if (= (layout_atom_p (signature_parser context) name) 0)
        0
        (if (< 0 (signature_parameter_index context signature name 0))
            0
            (if (= (deref (field-pointer context 'parameter_count))
                   (deref (field-pointer context 'parameter_capacity)))
                0
                (let ((entry (native_parameter_at
                              context (deref (field-pointer context
                                                          'parameter_count)))))
                  (store (field-pointer entry 'name) name)
                  (store (field-pointer entry 'type_ast) 0)
                  (store (field-pointer entry 'size) 0)
                  (store (field-pointer entry 'kind) 0)
                  (store (field-pointer context 'parameter_count)
                         (wrap+ (deref (field-pointer context
                                                     'parameter_count)) 1))
                  (store (field-pointer signature 'arity)
                         (wrap+ (deref (field-pointer signature 'arity)) 1))
                  1)))))

(defun signature_add_parameters (context signature name)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize name)
           (returns c-int))
  (if (= name 0)
      1
      (if (= (signature_add_parameter context signature name) 0)
          0
          (signature_add_parameters context signature
                                    (signature_next context name)))))

(defun signature_assign_parameter (context signature name type)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize name type)
           (returns c-int))
  (let ((position (signature_parameter_index context signature name 0)))
    (if (= position 0)
        0
        (let ((entry (native_parameter_at context (wrap- position 1)))
              (shape (deref (field-pointer
                             (deref (field-pointer context 'layouts))
                             'scratch))))
          (if (< 0 (deref (field-pointer entry 'type_ast)))
              0
              (progn
                (store (field-pointer entry 'type_ast) type)
                (store (field-pointer entry 'size)
                       (deref (field-pointer shape 'size)))
                (store (field-pointer entry 'kind)
                       (deref (field-pointer shape 'kind)))
                1))))))

(defun signature_assign_names (context signature name type)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize name type)
           (returns c-int))
  (if (= name 0)
      1
      (if (= (signature_assign_parameter context signature name type) 0)
          0
          (signature_assign_names context signature
                                  (signature_next context name) type))))

(defun signature_type_spec (context signature spec)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize spec)
           (returns c-int))
  (let ((type (signature_next context (signature_first context spec))))
    (let ((first_name (signature_next context type)))
      (if (= first_name 0)
          0
          (if (= (native_resolve_type
                  (deref (field-pointer context 'layouts)) type
                  (deref (field-pointer
                          (deref (field-pointer context 'layouts))
                          'scratch))) 0)
              0
              (signature_assign_names context signature first_name type))))))

(defun signature_result_spec (context signature spec)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize spec)
           (returns c-int))
  (let ((type (signature_next context (signature_first context spec))))
    (if (= type 0)
        0
        (if (< 0 (deref (field-pointer signature 'result_type)))
            0
            (if (< 0 (signature_next context type))
                0
                (let ((layouts (deref (field-pointer context 'layouts))))
                  (let ((shape (deref (field-pointer layouts 'scratch))))
                    (if (= (native_resolve_type layouts type shape) 0)
                        0
                        (progn
                          (store (field-pointer signature 'result_type) type)
                          (store (field-pointer signature 'result_size)
                                 (deref (field-pointer shape 'size)))
                          (store (field-pointer signature 'result_kind)
                                 (deref (field-pointer shape 'kind)))
                          1)))))))))

(defun signature_export_spec (context signature spec)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize spec)
           (returns c-int))
  (let ((value (signature_next context (signature_first context spec))))
    (if (= (deref (field-pointer signature 'exported)) 1)
        0
        (if (= (signature_word_p context value #x633a 2) 0)
            0
            (if (= (signature_next context value) 0)
                (progn (store (field-pointer signature 'exported) 1) 1)
                0)))))

(defun signature_parse_spec (context signature spec)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize spec)
           (returns c-int))
  (if (= (signature_list_p context spec) 0)
      0
      (let ((head (signature_first context spec)))
        (cond
          ((= (signature_word_p context head #x65707974 4) 1)
           (signature_type_spec context signature spec))
          ((= (signature_word_p context head #x736e7275746572 7) 1)
           (signature_result_spec context signature spec))
          ((= (signature_word_p context head #x74726f7078652d63 8) 1)
           (signature_export_spec context signature spec))
          ((= (signature_word_p context head #x74726f707865 6) 1)
           (signature_export_spec context signature spec))
          (t 0)))))

(defun signature_parse_specs (context signature spec)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize spec)
           (returns c-int))
  (if (= spec 0)
      1
      (if (= (signature_parse_spec context signature spec) 0)
          0
          (signature_parse_specs context signature
                                 (signature_next context spec)))))

(defun signature_all_typed_from (context index stop)
  (declare (type (ptr native_signature_context) context)
           (type usize index stop)
           (returns c-int))
  (if (= index stop)
      1
      (if (= (deref (field-pointer (native_parameter_at context index)
                                   'type_ast)) 0)
          0
          (signature_all_typed_from context (wrap+ index 1) stop))))

(defun signature_complete_p (context signature)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (returns c-int))
  (if (= (deref (field-pointer signature 'result_type)) 0)
      0
      (signature_all_typed_from
       context (deref (field-pointer signature 'first_parameter))
       (wrap+ (deref (field-pointer signature 'first_parameter))
              (deref (field-pointer signature 'arity))))))

(defun signature_header_valid_p (context name parameters declaration)
  (declare (type (ptr native_signature_context) context)
           (type usize name parameters declaration)
           (returns c-int))
  (if (= (layout_atom_p (signature_parser context) name) 0)
      0
      (if (= (signature_name_used_p context name 0) 1)
          0
          (if (= (signature_list_p context parameters) 0)
              0
              (if (= (signature_list_p context declaration) 0)
                  0
                  (if (= (signature_word_p
                          context (signature_first context declaration)
                          #x6572616c636564 7) 0)
                      0
                      (if (= (signature_next context declaration) 0)
                          0 1)))))))

(defun signature_initialize_header (context signature name parameters
                                     declaration)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize name parameters declaration)
           (returns c-int))
  (store (field-pointer signature 'name) name)
  (store (field-pointer signature 'first_parameter)
         (deref (field-pointer context 'parameter_count)))
  (store (field-pointer signature 'arity) 0)
  (store (field-pointer signature 'result_type) 0)
  (store (field-pointer signature 'exported) 0)
  (store (field-pointer signature 'body)
         (signature_next context declaration))
  (if (= (signature_add_parameters context signature
                                   (signature_first context parameters)) 0)
      0
      (signature_parse_specs
       context signature
       (signature_next context (signature_first context declaration)))))

(defun signature_set_header (context signature root)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize root)
           (returns c-int))
  (let ((name (signature_next context (signature_first context root))))
    (let ((parameters (signature_next context name)))
      (let ((declaration (signature_next context parameters)))
        (if (= (signature_header_valid_p
                context name parameters declaration) 0)
            0
            (signature_initialize_header
             context signature name parameters declaration))))))

(defun native_parse_signature (context root)
  (declare (type (ptr native_signature_context) context)
           (type usize root)
           (returns c-int)
           (c-export :c))
  (if (= (native_signature_form_p context root) 0)
      0
      (if (= (deref (field-pointer context 'signature_count))
             (deref (field-pointer context 'signature_capacity)))
          0
          (let ((signature
                 (native_signature_at
                  context (deref (field-pointer context 'signature_count)))))
            (if (= (signature_set_header context signature root) 0)
                0
                (if (= (signature_complete_p context signature) 0)
                    0
                    (progn
                      (store (field-pointer context 'signature_count)
                             (wrap+ (deref (field-pointer context
                                                         'signature_count))
                                    1))
                      1)))))))
