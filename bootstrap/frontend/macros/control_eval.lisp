(include "forms.lisp")

(defun native_macro_value_false_p (call value)
  (declare (type (ptr native_macro_call) call) (type usize value) (returns c-int))
  (let ((parser (native_macro_call_parser call)))
    (let ((node (parser_node parser value)))
      (if (if (= (deref (field-pointer node 'kind)) 1) (= (deref (field-pointer node 'first)) 0) nil) 1
          (let ((env (deref (field-pointer (deref (field-pointer parser 'environment)) 'environment))))
            (if (= (ast_symbol_identity parser value) (deref (field-pointer env 'nil_symbol))) 1 0))))))

(defun native_macro_eval_if (call head)
  (declare (type (ptr native_macro_call) call) (type usize head) (returns usize))
  (let ((registry (deref (field-pointer call 'registry))))
    (let ((predicate (native_macro_next registry head)))
      (let ((consequent (native_macro_next registry predicate)))
        (let ((alternative (native_macro_next registry consequent)))
          (if (if (= consequent 0) t (< 0 (native_macro_next registry alternative)))
              (native_macro_call_fail call 2)
              (let ((value (native_macro_eval call predicate)))
                (if (= value 0) 0
                    (if (= (native_macro_value_false_p call value) 1)
                        (if (= alternative 0) (native_macro_boolean_form call head 0)
                            (native_macro_eval call alternative))
                        (native_macro_eval call consequent))))))))))
