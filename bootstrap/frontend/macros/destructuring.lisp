(defun native_macro_destructuring_nil_form_p (call form)
  (declare (type (ptr native_macro_call) call) (type usize form) (returns c-int))
  (if (= form 0) 0
      (let ((parser (native_macro_call_parser call)))
        (let ((node (parser_node parser form)))
          (if (= (deref (field-pointer node 'kind)) 1)
              (if (= (deref (field-pointer node 'first)) 0) 1 0)
              (let ((reader (deref (field-pointer parser 'environment))))
                (if (= (ptr-address reader) 0) 0
                    (let ((env (deref (field-pointer reader 'environment))))
                      (if (= (ptr-address env) 0) 0
                          (if (= (ast_symbol_identity parser form)
                                 (deref (field-pointer env 'nil_symbol))) 1 0))))))))))

;; Standard quote/function reader prefixes denote two-element lists to a
;; macro expander. Normalize a private copy while keeping the caller AST intact.
(defun native_macro_pattern_prefix_symbol (call kind)
  (declare (type (ptr native_macro_call) call) (type u32 kind) (returns usize))
  (let ((env (deref (field-pointer (deref (field-pointer (native_macro_call_parser call)
                                                       'environment)) 'environment))))
    (let ((name-cursor (deref (field-pointer env 'name_cursor)))
          (name-result (deref (field-pointer env 'name_result)))
          (lookup-cursor (deref (field-pointer env 'lookup_cursor)))
          (lookup-result (deref (field-pointer env 'lookup_result)))
          (hash (deref (field-pointer env 'hash))))
      (let ((symbol (if (= kind 3)
                        (native_ct_find_symbol env 1 (ffi:c-string "QUOTE") 5)
                        (native_ct_find_symbol env 1 (ffi:c-string "FUNCTION") 8))))
        (store (field-pointer env 'name_cursor) name-cursor)
        (store (field-pointer env 'name_result) name-result)
        (store (field-pointer env 'lookup_cursor) lookup-cursor)
        (store (field-pointer env 'lookup_result) lookup-result)
        (store (field-pointer env 'hash) hash)
        symbol))))

(defun native_macro_pattern_prefix_list (call form kind)
  (declare (type (ptr native_macro_call) call) (type usize form)
           (type u32 kind) (returns usize))
  (let ((symbol (native_macro_pattern_prefix_symbol call kind)))
    (if (= symbol 0) (native_macro_call_fail call 4)
        (let ((list (native_macro_list_form call form)))
          (if (= list 0) 0
              (let ((head (native_macro_symbol_form call form symbol)))
                (if (= head 0) 0
                    (let ((parser (native_macro_call_parser call)))
                      (let ((datum (native_macro_copy_form call
                                     (deref (field-pointer (parser_node parser form) 'first)) 1)))
                        (if (= datum 0) 0
                            (progn (parser_append parser list head)
                                   (parser_append parser list datum)
                                   list)))))))))))

(defun native_macro_pattern_list (call form)
  (declare (type (ptr native_macro_call) call) (type usize form) (returns usize))
  (let ((kind (deref (field-pointer (parser_node (native_macro_call_parser call) form) 'kind))))
    (if (= kind 1) form
        (if (if (= kind 3) t (= kind 9))
            (native_macro_pattern_prefix_list call form kind)
            (native_macro_call_fail call 2)))))

(defun native_macro_bind_pattern_step (call parameter form sequence optional)
  (declare (type (ptr native_macro_call) call)
           (type usize parameter form) (type c-int sequence optional)
           (returns c-int))
  (let ((parser (native_macro_call_parser call))
        (registry (deref (field-pointer call 'registry))))
    (if (= sequence 0)
        (let ((pattern (parser_node parser parameter)))
          (if (= (deref (field-pointer pattern 'kind)) 1)
              (if (= (native_macro_destructuring_nil_form_p call form) 1)
                  (native_macro_bind_pattern_step
                    call (deref (field-pointer pattern 'first)) 0 1 0)
                  (let ((list (native_macro_pattern_list call form)))
                    (if (= list 0) 0
                        (native_macro_bind_pattern_step
                          call (deref (field-pointer pattern 'first))
                          (deref (field-pointer (parser_node parser list) 'first)) 1 0))))
              (native_macro_add_binding call parameter form)))
        (cond
          ((= parameter 0)
           (if (= form 0) 1 (progn (native_macro_call_fail call 2) 0)))
          ((= (native_macro_optional_marker_p registry parameter) 1)
           (if (= optional 1) (progn (native_macro_call_fail call 10) 0)
               (native_macro_bind_pattern_step
                 call (native_macro_next registry parameter) form 1 1)))
          ((= (native_macro_rest_marker_p registry parameter) 1)
           (progn (native_macro_call_fail call 10) 0))
          ((= (native_macro_key_marker_p registry parameter) 1)
           (progn (native_macro_call_fail call 10) 0))
          ((= (native_macro_aux_marker_p registry parameter) 1)
           (progn (native_macro_call_fail call 10) 0))
          ((= optional 1)
           (let ((value (native_macro_optional_value call parameter form)))
             (if (= value 0) 0
                 (if (= (native_macro_bind_pattern_step
                          call (native_macro_optional_name call parameter) value 0 0) 0) 0
                     (let ((supplied (native_macro_next registry
                                       (native_macro_optional_default call parameter))))
                       (if (= supplied 0)
                           (native_macro_bind_pattern_step
                             call (native_macro_next registry parameter)
                             (native_macro_next registry form) 1 optional)
                           (let ((flag (native_macro_boolean_form call supplied
                                        (if (= form 0) 0 1))))
                             (if (= flag 0) 0
                                 (if (= (native_macro_add_binding call supplied flag) 0) 0
                                     (native_macro_bind_pattern_step
                                       call (native_macro_next registry parameter)
                                       (native_macro_next registry form) 1 optional))))))))))
          ((= form 0) (progn (native_macro_call_fail call 2) 0))
          ((= (native_macro_bind_pattern_step call parameter form 0 0) 0) 0)
          (t (native_macro_bind_pattern_step
               call (native_macro_next registry parameter)
               (native_macro_next registry form) 1 optional))))))

(defun native_macro_bind_pattern (call parameter form)
  (declare (type (ptr native_macro_call) call) (type usize parameter form)
           (returns c-int))
  (native_macro_bind_pattern_step call parameter form 0 0))
