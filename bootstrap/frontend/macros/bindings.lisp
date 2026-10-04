(include "registry.lisp")

(defun native_macro_call_fail (call error)
  (declare (type (ptr native_macro_call) call) (type u32 error) (returns usize))
  (if (= (deref (field-pointer call 'error)) 0)
      (store (field-pointer call 'error) error) (wrap-cast u32 0))
  0)

(defun native_macro_call_parser (call)
  (declare (type (ptr native_macro_call) call) (returns (ptr psl_parser)))
  (native_macro_parser (deref (field-pointer call 'registry))))

(defun native_macro_binding_at (call index)
  (declare (type (ptr native_macro_call) call) (type usize index)
           (returns (ptr native_macro_binding)))
  (pointer+ (deref (field-pointer call 'bindings)) (wrap-cast isize (wrap- index 1))))

(defun native_macro_add_binding (call parameter form)
  (declare (type (ptr native_macro_call) call) (type usize parameter form) (returns c-int))
  (let ((count (deref (field-pointer call 'count))))
    (if (< count (deref (field-pointer call 'capacity)))
        (let ((next (wrap+ count 1)))
          (let ((binding (native_macro_binding_at call next)))
            (store (field-pointer binding 'symbol) (ast_symbol_identity (native_macro_call_parser call) parameter))
            (store (field-pointer binding 'form) form)
            (store (field-pointer call 'count) next)
            1))
        (progn (native_macro_call_fail call 1) 0))))

(defun native_macro_rest_shell (call parameters)
  (declare (type (ptr native_macro_call) call) (type usize parameters) (returns usize))
  (let ((parser (native_macro_call_parser call))
        (tree (deref (field-pointer (deref (field-pointer call 'registry)) 'tree))))
    (let ((reader (deref (field-pointer tree 'reader))))
      (if (< (deref (field-pointer parser 'count)) (deref (field-pointer reader 'capacity)))
          (let ((node (parser_node parser parameters)))
            (let ((rest (parser_new_node parser 1 (deref (field-pointer node 'start)) 0)))
              (if (= rest 0) (native_macro_call_fail call 1)
                  (progn
                    (store (field-pointer reader 'count) rest)
                    (let ((identity (pointer+ (deref (field-pointer reader 'identities))
                                               (wrap-cast isize (wrap- rest 1)))))
                      (store (field-pointer identity 'symbol) 0)
                      (store (field-pointer identity 'origin) (deref (field-pointer call 'origin))))
                    rest))))
          (native_macro_call_fail call 1)))))

(defun native_macro_rest_form (call parameters arguments)
  (declare (type (ptr native_macro_call) call) (type usize parameters arguments) (returns usize))
  (let ((rest (native_macro_rest_shell call parameters))
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
        (native_macro_add_binding call (native_macro_next (deref (field-pointer call 'registry)) parameters) form))))

(defun native_macro_bind_arguments (call parameters arguments)
  (declare (type (ptr native_macro_call) call) (type usize parameters arguments) (returns c-int))
  (cond
    ((= parameters 0)
     (if (= arguments 0) 1 (progn (native_macro_call_fail call 2) 0)))
    ((= (native_macro_rest_marker_p (deref (field-pointer call 'registry)) parameters) 1)
     (native_macro_bind_rest call parameters arguments))
    ((= arguments 0) (progn (native_macro_call_fail call 2) 0))
    ((= (native_macro_add_binding call parameters arguments) 0) 0)
    (t (native_macro_bind_arguments call
         (native_macro_next (deref (field-pointer call 'registry)) parameters)
         (native_macro_next (deref (field-pointer call 'registry)) arguments)))))

(defun native_macro_bound_form_from (call symbol index)
  (declare (type (ptr native_macro_call) call) (type usize symbol index) (returns usize))
  (if (< (deref (field-pointer call 'count)) index) 0
      (let ((later (native_macro_bound_form_from call symbol (wrap+ index 1))))
        (if (< 0 later) later
            (let ((binding (native_macro_binding_at call index)))
              (if (= (deref (field-pointer binding 'symbol)) symbol)
                  (deref (field-pointer binding 'form)) (wrap-cast usize 0)))))))

(defun native_macro_bound_form (call symbol)
  (declare (type (ptr native_macro_call) call) (type usize symbol) (returns usize))
  (native_macro_bound_form_from call symbol 1))

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
