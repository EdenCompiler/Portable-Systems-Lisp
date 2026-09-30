;; Packed records share field validation and metadata with natural C records.
;; Their fields use alignment one, including nested previously defined records.

(defun native_packed_layout_form_p (context root)
  (declare (type (ptr native_layout_context) context)
           (type usize root) (returns c-int))
  (let ((parser (deref (field-pointer context 'parser))))
    (if (= root 0) 0
        (if (= (deref (field-pointer (parser_node parser root) 'kind)) 1)
            (let ((head (deref (field-pointer (parser_node parser root) 'first))))
              (ast_long_word_p parser (deref (field-pointer context 'source))
                               head #x6375727473666564 #x64656b6361702f74 16))
            0))))

(defun native_register_packed_layout (context root)
  (declare (type (ptr native_layout_context) context)
           (type usize root) (returns c-int))
  (if (= (native_packed_layout_form_p context root) 0) 0
      (let ((parser (deref (field-pointer context 'parser))))
        (let ((head (deref (field-pointer (parser_node parser root) 'first))))
          (let ((name (deref (field-pointer (parser_node parser head) 'next))))
            (if (= (layout_source_identifier_p context name) 0) 0
                (if (< 0 (native_find_layout context name)) 0
                    (if (= (deref (field-pointer context 'layout_count))
                           (deref (field-pointer context 'layout_capacity))) 0
                        (native_register_layout_mode
                         context name
                         (deref (field-pointer (parser_node parser name) 'next))
                         1)))))))))
