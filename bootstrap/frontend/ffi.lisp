;; Imported C signatures use the same resolved type and parameter records as
;; ordinary functions. Their names become atom slices after string validation.
(defun native_import_form_p (context root)
  (declare (type (ptr native_signature_context) context)
           (type usize root) (returns c-int) (c-export :c))
  (if (= (signature_list_p context root) 0) 0
      (let ((head (signature_first context root))
            (parser (signature_parser context))
            (source (deref (field-pointer (deref (field-pointer context 'layouts)) 'source))))
        (if (= head 0) 0
            (let ((node (parser_node parser head)))
              (if (= (deref (field-pointer node 'kind)) 8)
                  (if (= (deref (field-pointer node 'length)) 19)
                      (let ((start (deref (field-pointer node 'start))))
                        (if (= (ascii_matches source start #x6f706d693a696666 8) 1)
                            (if (= (ascii_matches source (wrap+ start 8) #x74636e75662d7472 8) 1)
                                (ascii_matches source (wrap+ start 16) #x6e6f69 3) 0) 0))
                      0) 0))))))

(defun import_name_atom (context reference)
  (declare (type (ptr native_signature_context) context)
           (type usize reference) (returns usize))
  (if (= reference 0) 0
      (let ((parser (signature_parser context))
            (source (deref (field-pointer (deref (field-pointer context 'layouts)) 'source))))
        (let ((node (parser_node parser reference)))
          (if (= (deref (field-pointer node 'kind)) 7)
              (let ((length (deref (field-pointer node 'length)))
                    (start (wrap+ (deref (field-pointer node 'start)) 1)))
                (if (< length 3) 0
                    (if (= (simple_export_name_p source start (wrap- length 2)) 1)
                        (parser_new_node parser 8 start (wrap- length 2)) 0)))
              0)))))

(defun import_parameter (context signature specification)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize specification) (returns c-int))
  (if (= (signature_list_p context specification) 0) 0
      (let ((name (signature_first context specification)))
        (let ((type (signature_next context name)))
          (if (= type 0) 0
              (if (= (signature_next context type) 0)
                  (if (= (signature_add_parameter context signature name) 0) 0
                      (let ((layouts (deref (field-pointer context 'layouts))))
                        (if (= (native_resolve_type layouts type (deref (field-pointer layouts 'scratch))) 0) 0
                            (signature_assign_parameter context signature name type))))
                  0))))))

(defun import_parameters (context signature specification)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize specification) (returns c-int))
  (if (= specification 0) 1
      (if (= (import_parameter context signature specification) 0) 0
          (import_parameters context signature (signature_next context specification)))))

(defun import_result (context signature type)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize type) (returns c-int))
  (let ((layouts (deref (field-pointer context 'layouts))))
    (let ((shape (deref (field-pointer layouts 'scratch))))
      (if (= (native_resolve_type layouts type shape) 0) 0
          (progn
            (store (field-pointer signature 'result_type) type)
            (store (field-pointer signature 'result_size) (deref (field-pointer shape 'size)))
            (store (field-pointer signature 'result_kind) (deref (field-pointer shape 'kind)))
            1)))))

(defun import_initialize (context signature name parameters result)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize name parameters result) (returns c-int))
  (store (field-pointer signature 'name) name)
  (store (field-pointer signature 'first_parameter) (deref (field-pointer context 'parameter_count)))
  (store (field-pointer signature 'arity) 0)
  (store (field-pointer signature 'body) 0)
  (store (field-pointer signature 'exported) 0)
  (store (field-pointer signature 'imported) 1)
  (store (field-pointer signature 'allocation_free) 0)
  (store (field-pointer signature 'effect_ready) 1)
  (store (field-pointer signature 'inline_base) 0)
  (store (field-pointer signature 'inline_count) 0)
  (store (field-pointer signature 'inline_result) 0)
  (if (= (import_parameters context signature (signature_first context parameters)) 0) 0
      (import_result context signature result)))

(defun import_effect (context signature annotation)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature) (type usize annotation) (returns c-int))
  (if (= annotation 0) 1
      (if (= (signature_next context annotation) 0)
          (if (= (ast_long_word_p (signature_parser context)
                   (deref (field-pointer (deref (field-pointer context 'layouts)) 'source))
                   annotation #x6f6c6c612d6f6e3a #x6e6f69746163 14) 1)
              (progn (store (field-pointer signature 'allocation_free) 1) 1) 0) 0)))

(defun import_header (context signature root)
  (declare (type (ptr native_signature_context) context)
           (type (ptr native_signature) signature)
           (type usize root) (returns c-int))
  (let ((raw_name (signature_next context (signature_first context root))))
    (let ((parameters (signature_next context raw_name))
          (name (import_name_atom context raw_name)))
      (let ((arrow (signature_next context parameters)))
        (let ((result (signature_next context arrow)))
          (if (= name 0) 0
              (if (= (signature_name_used_p context name 0) 1) 0
                  (if (= (signature_list_p context parameters) 0) 0
                      (if (= (signature_word_p context arrow #x3e2d 2) 0) 0
                          (if (= result 0) 0
                              (if (= (import_initialize context signature name parameters result) 0) 0
                                  (import_effect context signature (signature_next context result)))))))))))))

(defun native_parse_import (context root)
  (declare (type (ptr native_signature_context) context)
           (type usize root) (returns c-int) (c-export :c))
  (if (= (native_import_form_p context root) 0) 0
      (if (= (deref (field-pointer context 'signature_count))
             (deref (field-pointer context 'signature_capacity))) 0
          (let ((signature (native_signature_at context (deref (field-pointer context 'signature_count)))))
            (if (= (import_header context signature root) 0) 0
                (if (= (signature_complete_p context signature) 0) 0
                    (progn
                      (store (field-pointer context 'signature_count)
                             (wrap+ (deref (field-pointer context 'signature_count)) 1))
                      1)))))))
