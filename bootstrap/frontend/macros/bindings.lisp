(include "aux_bindings.lisp")
(defun native_macro_rest_form (call parameters arguments)
  (declare (type (ptr native_macro_call) call) (type usize parameters arguments) (returns usize))
  (let ((rest (native_macro_list_form call parameters))
        (tree (deref (field-pointer (deref (field-pointer call 'registry)) 'tree))))
    (if (= rest 0) 0
        (let ((origin (deref (field-pointer tree 'origin))))
          (store (field-pointer tree 'origin) 0)
          (let ((status (native_tree_copy_children tree rest arguments)))
            (store (field-pointer tree 'origin) origin)
            (if (= status 1) rest
                (native_macro_call_fail call (deref (field-pointer tree 'error)))))))))

(defun native_macro_bind_rest (call parameters arguments)
  (declare (type (ptr native_macro_call) call) (type usize parameters arguments) (returns c-int))
  (let ((form (native_macro_rest_form call parameters arguments)))
    (if (= form 0) 0
        (let ((registry (deref (field-pointer call 'registry))))
          (let ((name (native_macro_next registry parameters)))
            (if (= (native_macro_add_binding call name form) 0) 0
                (let ((tail (native_macro_next registry name)))
                  (if (= tail 0) 1
                      (native_macro_bind_aux call (native_macro_next registry tail))))))))))

(defun native_macro_bind_arguments_from (call parameters arguments optional)
  (declare (type (ptr native_macro_call) call) (type usize parameters arguments)
           (type c-int optional) (returns c-int))
  (let ((registry (deref (field-pointer call 'registry))))
    (cond
      ((= parameters 0)
       (if (= arguments 0) 1 (progn (native_macro_call_fail call 2) 0)))
      ((= (native_macro_whole_marker_p registry parameters) 1)
       (let ((name (native_macro_next registry parameters)))
         (if (= (native_macro_add_binding call name (deref (field-pointer call 'origin))) 0) 0
             (native_macro_bind_arguments_from call (native_macro_next registry name) arguments optional))))
      ((= (native_macro_aux_marker_p registry parameters) 1)
       (if (= arguments 0) (native_macro_bind_aux call (native_macro_next registry parameters))
           (progn (native_macro_call_fail call 2) 0)))
      ((= (native_macro_optional_marker_p registry parameters) 1)
       (native_macro_bind_arguments_from call (native_macro_next registry parameters) arguments 1))
      ((= (native_macro_rest_marker_p registry parameters) 1)
       (native_macro_bind_rest call parameters arguments))
      ((= optional 1)
       (if (= (native_macro_bind_optional call parameters arguments) 0) 0
           (native_macro_bind_arguments_from call (native_macro_next registry parameters)
                                            (native_macro_next registry arguments) optional)))
      ((= arguments 0) (progn (native_macro_call_fail call 2) 0))
      ((= (native_macro_add_binding call parameters arguments) 0) 0)
      (t (native_macro_bind_arguments_from call (native_macro_next registry parameters)
                                           (native_macro_next registry arguments) optional)))))

(defun native_macro_bind_arguments (call parameters arguments)
  (declare (type (ptr native_macro_call) call) (type usize parameters arguments) (returns c-int))
  (native_macro_bind_arguments_from call parameters arguments 0))

(defun native_macro_prepare_call (call definition form)
  (declare (type (ptr native_macro_call) call) (type usize definition form)
           (returns c-int) (c-export :c))
  (let ((registry (deref (field-pointer call 'registry)))
        (parser (native_macro_call_parser call)))
    (store (field-pointer call 'count) 0)
    (store (field-pointer call 'origin) form)
    (if (< 0 (deref (field-pointer call 'error))) 0
        (if (= (native_tree_verify (deref (field-pointer registry 'tree)) form) 0)
            (progn (native_macro_call_fail call 4) 0)
            (if (if (= definition 0) t (< (deref (field-pointer registry 'count)) definition))
                (progn (native_macro_call_fail call 4) 0)
                (let ((record (native_macro_definition_at registry definition)))
                  (let ((head (deref (field-pointer (parser_node parser form) 'first))))
                    (if (= (ast_symbol_identity parser head) (deref (field-pointer record 'symbol)))
                        (if (= (native_macro_bind_arguments call
                             (deref (field-pointer (parser_node parser (deref (field-pointer record 'parameters))) 'first))
                             (native_macro_next registry head)) 1) 1
                            (progn (store (field-pointer call 'count) 0) 0))
                        (progn (native_macro_call_fail call 4) 0)))))))))
