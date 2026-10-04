(include "sequence_eval.lisp")

(defun native_macro_eval_list_elements (call parent arguments)
  (declare (type (ptr native_macro_call) call) (type usize parent arguments) (returns c-int))
  (let ((tree (native_macro_tree call)) (registry (deref (field-pointer call 'registry)))
        (parser (native_macro_call_parser call)))
    (store (field-pointer tree 'cursor) arguments)
    (while (if (= (deref (field-pointer call 'error)) 0)
               (< 0 (deref (field-pointer tree 'cursor))) nil)
      (let ((argument (deref (field-pointer tree 'cursor))))
        (let ((next (native_macro_next registry argument)) (value (native_macro_eval call argument)))
          (if (= value 0) (wrap-cast usize 0) (parser_append parser parent value))
          (store (field-pointer tree 'cursor) next))))
    (if (= (deref (field-pointer call 'error)) 0) 1 0)))

(defun native_macro_eval_list_constructor (call head)
  (declare (type (ptr native_macro_call) call) (type usize head) (returns usize))
  (let ((list (native_macro_list_form call head)))
    (if (= list 0) 0
        (if (= (native_macro_eval_list_elements call list
                 (native_macro_next (deref (field-pointer call 'registry)) head)) 1) list 0))))
