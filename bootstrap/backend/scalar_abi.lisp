;; Shared class tags for scalar ABI argument locations. The low word is the
;; register number or stack slot; the high word is the location class.
(defun native_abi_location (class index)
  (declare (type usize class index) (returns usize))
  (wrap+ (wrap* class #x100000000) index))

(defun native_abi_location_class (location)
  (declare (type usize location) (returns usize))
  (wrap-cast usize (shr64 (wrap-cast u64 location) 32)))

(defun native_abi_location_index (location)
  (declare (type usize location) (returns usize))
  (bits-and location #xffffffff))

(defun native_abi_float_p (code)
  (declare (type u32 code) (returns c-int))
  (if (= code 13) 1 (if (= code 14) 1 0)))

(defun native_abi_float_parameters_p (context index)
  (declare (type (ptr native_compile_context) context) (type usize index)
           (returns c-int))
  (let ((signature (deref (field-pointer context 'current_signature))))
    (if (= (ptr-address signature) 0) 0
        (if (= index (deref (field-pointer signature 'arity))) 0
            (if (= (native_abi_float_p
                    (scalar_signature_parameter_code context signature index)) 1) 1
                (native_abi_float_parameters_p context (wrap+ index 1)))))))
