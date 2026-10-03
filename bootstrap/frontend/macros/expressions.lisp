(include "expand.lisp")

(defun native_macro_head_p (call form a b length)
  (declare (type (ptr native_macro_call) call) (type usize form length)
           (type u64 a b) (returns c-int))
  (let ((registry (deref (field-pointer call 'registry)))
        (parser (native_macro_call_parser call)))
    (ast_builtin_word_p parser (deref (field-pointer registry 'source))
       (deref (field-pointer (parser_node parser form) 'first)) a b length)))

(defun native_macro_clone_shell (call form)
  (declare (type (ptr native_macro_call) call) (type usize form) (returns usize))
  (let ((tree (native_macro_tree call)))
    (let ((origin (deref (field-pointer tree 'origin))))
      (store (field-pointer tree 'origin) 0)
      (let ((copy (native_macro_new_template_node call form)))
        (store (field-pointer tree 'origin) origin)
        copy))))

(defun native_macro_expression_arguments (call parent reference)
  (declare (type (ptr native_macro_call) call) (type usize parent reference) (returns c-int))
  (let ((tree (native_macro_tree call)) (parser (native_macro_call_parser call)))
    (store (field-pointer tree 'cursor) reference)
    (while (if (= (deref (field-pointer call 'error)) 0)
               (< 0 (deref (field-pointer tree 'cursor))) nil)
      (let ((child (deref (field-pointer tree 'cursor))))
        (let ((next (deref (field-pointer (parser_node parser child) 'next)))
              (copy (native_macro_expression call child)))
          (if (= copy 0) (wrap-cast usize 0) (parser_append parser parent copy))
          (store (field-pointer tree 'cursor) next))))
    (if (= (deref (field-pointer call 'error)) 0) 1 0)))

(defun native_macro_append_static (call parent reference)
  (declare (type (ptr native_macro_call) call) (type usize parent reference) (returns c-int))
  (if (< 0 (deref (field-pointer call 'error))) 0
      (if (if (= parent 0) t (= reference 0)) (progn (native_macro_call_fail call 4) 0)
          (let ((copy (native_macro_copy_form call reference 1)))
            (if (= copy 0) 0
                (progn (parser_append (native_macro_call_parser call) parent copy) 1))))))

(defun native_macro_binding_expression (call reference)
  (declare (type (ptr native_macro_call) call) (type usize reference) (returns usize))
  (let ((parser (native_macro_call_parser call)))
    (let ((node (parser_node parser reference)))
      (if (if (= (deref (field-pointer node 'kind)) 1) nil t)
          (native_macro_copy_form call reference 1)
          (let ((copy (native_macro_clone_shell call reference)))
            (let ((name (deref (field-pointer node 'first))))
              (if (= name 0) copy
                  (if (= (native_macro_append_static call copy name) 0) 0
                      (if (= (native_macro_expression_arguments call copy
                               (native_macro_next (deref (field-pointer call 'registry)) name)) 1)
                          copy (wrap-cast usize 0))))))))))

(defun native_macro_binding_list (call reference)
  (declare (type (ptr native_macro_call) call) (type usize reference) (returns usize))
  (let ((tree (native_macro_tree call)) (parser (native_macro_call_parser call)))
    (let ((node (parser_node parser reference)))
      (if (if (= (deref (field-pointer node 'kind)) 1) nil t)
          (native_macro_copy_form call reference 1)
          (let ((copy (native_macro_clone_shell call reference)))
            (store (field-pointer tree 'cursor) (deref (field-pointer node 'first)))
            (while (if (= (deref (field-pointer call 'error)) 0)
                       (< 0 (deref (field-pointer tree 'cursor))) nil)
              (let ((child (deref (field-pointer tree 'cursor))))
                (let ((next (deref (field-pointer (parser_node parser child) 'next)))
                      (binding (native_macro_binding_expression call child)))
                  (if (= binding 0) (wrap-cast usize 0) (parser_append parser copy binding))
                  (store (field-pointer tree 'cursor) next))))
            (if (= (deref (field-pointer call 'error)) 0) copy (wrap-cast usize 0)))))))

(defun native_macro_let_expression (call reference)
  (declare (type (ptr native_macro_call) call) (type usize reference) (returns usize))
  (let ((registry (deref (field-pointer call 'registry)))
        (parser (native_macro_call_parser call)))
    (let ((head (deref (field-pointer (parser_node parser reference) 'first)))
          (copy (native_macro_clone_shell call reference)))
      (let ((bindings (native_macro_next registry head)))
        (if (= bindings 0) (native_macro_call_fail call 4)
            (if (= (native_macro_append_static call copy head) 0) 0
                (let ((list (native_macro_binding_list call bindings)))
                  (if (= list 0) 0
                      (progn
                        (parser_append parser copy list)
                        (if (= (native_macro_expression_arguments call copy (native_macro_next registry bindings)) 1)
                            copy (wrap-cast usize 0)))))))))))

(defun native_macro_cond_expression (call reference)
  (declare (type (ptr native_macro_call) call) (type usize reference) (returns usize))
  (let ((tree (native_macro_tree call)) (parser (native_macro_call_parser call)))
    (let ((head (deref (field-pointer (parser_node parser reference) 'first)))
          (copy (native_macro_clone_shell call reference)))
      (native_macro_append_static call copy head)
      (store (field-pointer tree 'cursor) (native_macro_next (deref (field-pointer call 'registry)) head))
      (while (if (= (deref (field-pointer call 'error)) 0)
                 (< 0 (deref (field-pointer tree 'cursor))) nil)
        (let ((clause (deref (field-pointer tree 'cursor))))
          (let ((next (deref (field-pointer (parser_node parser clause) 'next)))
                (new (native_macro_clone_shell call clause)))
            (if (= (native_macro_expression_arguments call new
                     (deref (field-pointer (parser_node parser clause) 'first))) 1)
                (parser_append parser copy new) (wrap-cast usize 0))
            (store (field-pointer tree 'cursor) next))))
      (if (= (deref (field-pointer call 'error)) 0) copy (wrap-cast usize 0)))))

(defun native_macro_static_first_p (call reference)
  (declare (type (ptr native_macro_call) call) (type usize reference) (returns c-int))
  (cond
    ((= (native_macro_head_p call reference #x7361632d70617277 #x74 9) 1) 1)
    ((= (native_macro_head_p call reference #x747361632d727470 0 8) 1) 1)
    ((= (native_macro_head_p call reference #x6d6f72662d727470 #x737365726464612d 16) 1) 1)
    ((= (native_macro_head_p call reference #x6c6c61633a696666 0 8) 1) 1)
    (t 0)))

(defun native_macro_general_expression (call reference)
  (declare (type (ptr native_macro_call) call) (type usize reference) (returns usize))
  (let ((registry (deref (field-pointer call 'registry)))
        (parser (native_macro_call_parser call)))
    (let ((head (deref (field-pointer (parser_node parser reference) 'first)))
          (copy (native_macro_clone_shell call reference)))
      (if (= head 0) copy
          (if (= (native_macro_append_static call copy head) 0) 0
              (let ((argument (native_macro_next registry head)))
                (if (if (= (native_macro_static_first_p call reference) 1) (< 0 argument) nil)
                    (if (= (native_macro_append_static call copy argument) 0) 0
                        (if (= (native_macro_expression_arguments call copy (native_macro_next registry argument)) 1)
                            copy (wrap-cast usize 0)))
                    (if (= (native_macro_expression_arguments call copy argument) 1)
                        copy (wrap-cast usize 0)))))))))

(defun native_macro_expression_body (call reference)
  (declare (type (ptr native_macro_call) call) (type usize reference) (returns usize))
  (let ((parser (native_macro_call_parser call))
        (result (field-pointer call 'repeated)))
    (if (= (native_macroexpand call reference result) 0) 0
        (let ((form (deref (field-pointer result 'form))))
          (if (if (= (deref (field-pointer (parser_node parser form) 'kind)) 1) nil t)
              (native_macro_copy_form call form 1)
              (cond
                ((= (native_macro_head_p call form #x74656c 0 3) 1) (native_macro_let_expression call form))
                ((= (native_macro_head_p call form #x2a74656c 0 4) 1) (native_macro_let_expression call form))
                ((= (native_macro_head_p call form #x646e6f63 0 4) 1) (native_macro_cond_expression call form))
                ((if (= (native_macro_head_p call form #x65746f7571 0 5) 1) t
                     (if (= (native_macro_head_p call form #x666f657a6973 0 6) 1) t
                         (if (= (native_macro_head_p call form #x666f6e67696c61 0 7) 1) t
                             (= (native_macro_head_p call form #x6f2d74657366666f #x66 9) 1))))
                 (native_macro_copy_form call form 1))
                (t (native_macro_general_expression call form))))))))

(defun native_macro_expression (call reference)
  (declare (type (ptr native_macro_call) call) (type usize reference) (returns usize))
  (let ((tree (native_macro_tree call)))
    (if (< 0 (deref (field-pointer call 'error))) 0
        (if (< (deref (field-pointer tree 'depth)) (deref (field-pointer tree 'limit)))
            (progn
              (store (field-pointer tree 'depth) (wrap+ (deref (field-pointer tree 'depth)) 1))
              (let ((copy (native_macro_expression_body call reference)))
                (store (field-pointer tree 'depth) (wrap- (deref (field-pointer tree 'depth)) 1))
                copy))
            (native_macro_call_fail call 5)))))
