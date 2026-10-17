(include "registry.lisp")

(ffi:import-function "psl_rt_value_handle_get" ((token usize)) -> value :no-allocation)
(ffi:import-function "psl_rt_value_handle_set" ((token usize) (item value)) -> void :no-allocation)

(defun native_macro_call_fail (call error)
  (declare (type (ptr native_macro_call) call) (type u32 error)
           (returns usize))
  (if (= (deref (field-pointer call 'error)) 0)
      (progn (store (field-pointer call 'error) error) 0) 0)
  0)

(defun native_macro_call_parser (call)
  (declare (type (ptr native_macro_call) call) (returns (ptr psl_parser)))
  (native_macro_parser (deref (field-pointer call 'registry))))

(defun native_macro_binding_vector_extend (call vector length capacity)
  (declare (type (ptr native_macro_call) call) (type value vector)
           (type usize length capacity) (returns value))
  (if (< length capacity)
      (progn
        (psl:value-vector-push vector nil)
        (native_macro_binding_vector_extend call vector
          (wrap+ length 1) capacity))
      vector))

(defun native_macro_binding_vector (call)
  (declare (type (ptr native_macro_call) call) (returns value))
  (let ((handle (deref (field-pointer call 'binding_handle))))
    (let ((vector (ffi:call psl_rt_value_handle_get handle)))
      (if (cl:eq vector nil)
          (let ((created (psl:make-value-vector
                          (deref (field-pointer call 'capacity)) nil)))
            (ffi:call psl_rt_value_handle_set handle created)
            created)
          (native_macro_binding_vector_extend call vector
            (psl:value-vector-length vector)
            (deref (field-pointer call 'capacity)))))))

(defun native_macro_box_reference (call reference)
  (declare (type (ptr native_macro_call) call) (type usize reference)
           (returns value))
  (if (< #x3fffffffffffffff reference)
      (progn (native_macro_call_fail call 4) nil)
      (psl:box-fixnum (wrap-cast s64 reference))))

(defun native_macro_binding_symbol_at (call index)
  (declare (type (ptr native_macro_call) call) (type usize index)
           (returns usize) (c-export :c))
  (let ((pair (psl:value-vector-ref (native_macro_binding_vector call)
                                    (wrap- index 1))))
    (wrap-cast usize (psl:unbox-fixnum (cl:car pair)))))

(defun native_macro_binding_form_at (call index)
  (declare (type (ptr native_macro_call) call) (type usize index)
           (returns usize) (c-export :c))
  (let ((pair (psl:value-vector-ref (native_macro_binding_vector call)
                                    (wrap- index 1))))
    (wrap-cast usize (psl:unbox-fixnum (cl:cdr pair)))))

(defun native_macro_binding_set_at (call index symbol form)
  (declare (type (ptr native_macro_call) call) (type usize index symbol form)
           (returns c-int) (c-export :c))
  (let ((vector (native_macro_binding_vector call)))
    (let ((boxed_symbol (native_macro_box_reference call symbol))
          (boxed_form (native_macro_box_reference call form)))
      (if (< 0 (deref (field-pointer call 'error)))
          0
          (progn
            (psl:value-vector-set vector (wrap- index 1)
                                  (cl:cons boxed_symbol boxed_form))
            1)))))

(defun native_macro_binding_values_valid (call symbol form boxed_symbol boxed_form)
  (declare (type (ptr native_macro_call) call) (type usize symbol form)
           (type value boxed_symbol boxed_form) (returns c-int))
  (if (< 0 (deref (field-pointer call 'error))) 0
      (if (cl:eq boxed_symbol nil) 0
          (if (cl:eq boxed_form nil) 0 1))))

(defun native_macro_clear_bindings_between (call vector index stop)
  (declare (type (ptr native_macro_call) call) (type value vector)
           (type usize index stop) (returns c-int))
  (if (if (= index stop) t (< index stop)) 1
      (progn
        (psl:value-vector-set vector (wrap- index 1) nil)
        (native_macro_clear_bindings_between call vector (wrap- index 1) stop))))

(defun native_macro_truncate_bindings (call new_count)
  (declare (type (ptr native_macro_call) call) (type usize new_count)
           (returns c-int) (c-export :c))
  (let ((count (deref (field-pointer call 'count))))
    (if (< count new_count) (progn (native_macro_call_fail call 4) 0)
        (if (= count new_count) 1
            (let ((vector (native_macro_binding_vector call)))
              (if (= (native_macro_clear_bindings_between call vector count new_count) 1)
                  (progn (store (field-pointer call 'count) new_count) 1) 0))))))

(defun native_macro_clear_bindings (call)
  (declare (type (ptr native_macro_call) call) (returns c-int))
  (native_macro_truncate_bindings call 0))

(defun native_macro_add_binding (call parameter form)
  (declare (type (ptr native_macro_call) call) (type usize parameter form)
           (returns c-int))
  (let ((count (deref (field-pointer call 'count)))
        (capacity (deref (field-pointer call 'capacity))))
    (if (if (= parameter 0) t (= form 0))
        (progn (native_macro_call_fail call 4) 0)
    (if (< count capacity)
        (let ((vector (native_macro_binding_vector call))
              (symbol (ast_symbol_identity (native_macro_call_parser call) parameter)))
          (let ((boxed_symbol (native_macro_box_reference call symbol))
                (boxed_form (native_macro_box_reference call form)))
            (if (= (native_macro_binding_values_valid
                    call symbol form boxed_symbol boxed_form) 0) 0
                (let ((pair (cl:cons boxed_symbol boxed_form)))
                  (psl:value-vector-set vector count pair)
                  (store (field-pointer call 'count) (wrap+ count 1))
                  1))))
        (progn (native_macro_call_fail call 1) 0)))))

(defun native_macro_bound_form_from (call symbol index)
  (declare (type (ptr native_macro_call) call) (type usize symbol index)
           (returns usize))
  (if (< (deref (field-pointer call 'count)) index) 0
      (let ((later (native_macro_bound_form_from call symbol (wrap+ index 1))))
        (if (< 0 later) later
              (if (= (native_macro_binding_symbol_at call index) symbol)
                  (native_macro_binding_form_at call index) 0)))))

(defun native_macro_bound_form (call symbol)
  (declare (type (ptr native_macro_call) call) (type usize symbol)
           (returns usize))
  (if (= symbol 0) 0 (native_macro_bound_form_from call symbol 1)))

(defun native_macro_tree (call)
  (declare (type (ptr native_macro_call) call) (returns (ptr native_tree_context)))
  (deref (field-pointer (deref (field-pointer call 'registry)) 'tree)))
