(include "eval.lisp")

(defun native_macro_optional_name (call parameter)
  (declare (type (ptr native_macro_call) call) (type usize parameter) (returns usize))
  (let ((node (parser_node (native_macro_call_parser call) parameter)))
    (if (= (deref (field-pointer node 'kind)) 1) (deref (field-pointer node 'first)) parameter)))

(defun native_macro_optional_default (call parameter)
  (declare (type (ptr native_macro_call) call) (type usize parameter) (returns usize))
  (let ((node (parser_node (native_macro_call_parser call) parameter)))
    (if (= (deref (field-pointer node 'kind)) 1)
        (native_macro_next (deref (field-pointer call 'registry)) (deref (field-pointer node 'first))) 0)))

(defun native_macro_default_value (call parameter default)
  (declare (type (ptr native_macro_call) call) (type usize parameter default) (returns usize))
  (if (= default 0) (native_macro_boolean_form call parameter 0)
      (let ((tree (native_macro_tree call)))
        (let ((origin (deref (field-pointer tree 'origin))))
          (store (field-pointer tree 'origin) (deref (field-pointer call 'origin)))
          (let ((value (native_macro_eval call default)))
            (store (field-pointer tree 'origin) origin)
            value)))))

(defun native_macro_optional_value (call parameter argument)
  (declare (type (ptr native_macro_call) call) (type usize parameter argument) (returns usize))
  (if (< 0 argument) argument
      (native_macro_default_value call parameter (native_macro_optional_default call parameter))))

(defun native_macro_bind_optional (call parameter argument)
  (declare (type (ptr native_macro_call) call) (type usize parameter argument) (returns c-int))
  (let ((value (native_macro_optional_value call parameter argument)))
    (if (= value 0) 0
        (if (= (native_macro_add_binding call (native_macro_optional_name call parameter) value) 0) 0
            (let ((supplied (native_macro_next (deref (field-pointer call 'registry))
                                             (native_macro_optional_default call parameter))))
              (if (= supplied 0) 1
                  (let ((flag (native_macro_boolean_form call supplied (if (= argument 0) 0 1))))
                    (if (= flag 0) 0 (native_macro_add_binding call supplied flag)))))))))
