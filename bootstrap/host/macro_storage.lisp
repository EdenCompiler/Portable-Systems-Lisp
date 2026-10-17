;; Compiler-owned macro vectors are rooted by distinct host runtime handles.
(ffi:import-function "psl_rt_value_handle_open" () -> usize)
(ffi:import-function "psl_rt_value_handle_close" ((token usize)) -> void :no-allocation)

(defun native_allocate_macros (storage)
  (declare (type (ptr native_storage) storage) (returns c-int))
  (store (field-pointer storage 'macro_definition_handle)
         (ffi:call psl_rt_value_handle_open))
  (store (field-pointer storage 'macro_binding_handle)
         (ffi:call psl_rt_value_handle_open))
  (if (= (deref (field-pointer storage 'macro_definition_handle)) 0) 0
      (if (= (deref (field-pointer storage 'macro_binding_handle)) 0) 0 1)))

(defun native_release_macros (storage)
  (declare (type (ptr native_storage) storage) (returns c-int))
  (let ((definitions (deref (field-pointer storage 'macro_definition_handle))))
    (if (= definitions 0) 0
        (progn (ffi:call psl_rt_value_handle_close definitions) 1)))
  (store (field-pointer storage 'macro_definition_handle) 0)
  (let ((handle (deref (field-pointer storage 'macro_binding_handle))))
    (if (= handle 0) 0
        (progn (ffi:call psl_rt_value_handle_close handle) 1)))
  (store (field-pointer storage 'macro_binding_handle) 0)
  1)
