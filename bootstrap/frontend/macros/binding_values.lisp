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

(defun native_macro_tree (call)
  (declare (type (ptr native_macro_call) call) (returns (ptr native_tree_context)))
  (deref (field-pointer (deref (field-pointer call 'registry)) 'tree)))
