(include "optional_bindings.lisp")

(defun native_macro_bind_aux (call parameters)
  (declare (type (ptr native_macro_call) call) (type usize parameters) (returns c-int))
  (if (= parameters 0) 1
      (let ((value (native_macro_default_value call parameters (native_macro_optional_default call parameters))))
        (if (= value 0) 0
            (if (= (native_macro_add_binding call (native_macro_optional_name call parameters) value) 0) 0
                (native_macro_bind_aux call (native_macro_next (deref (field-pointer call 'registry)) parameters)))))))
