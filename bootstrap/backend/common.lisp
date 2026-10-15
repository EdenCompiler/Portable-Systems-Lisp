(include "common_types.lisp")
;; Function descriptors are supplied in source order. Their code spans must
;; partition the .text bytes. Imports have zero spans and become undefined
;; symbols only when referenced. Names are ASCII slices of caller-owned source.
(defun native_function_at (functions index)
  (declare (type (ptr native_function) functions)
           (type usize index)
           (returns (ptr native_function)))
  (pointer+ functions (wrap-cast isize index)))

(defun native_function_defined_target_from (functions index target)
  (declare (type (ptr native_function) functions)
           (type usize index target) (returns c-int))
  (if (= index target) 1
      (if (= (deref (field-pointer (native_function_at functions index) 'imported)) 1) 0
          (native_function_defined_target_from functions (wrap+ index 1) target))))

(defun native_function_defined_target_p (functions count target)
  (declare (type (ptr native_function) functions)
           (type usize count target) (returns c-int))
  (if (= target 0) 0
      (if (= (ptr-address functions) 0) 0
          (if (< count target) 0
              (if (= (deref (field-pointer (native_function_at functions
                                            (wrap- target 1)) 'imported)) 1) 0
                  (native_function_defined_target_from functions 0 (wrap- target 1)))))))

(defun native_function_global_p (function)
  (declare (type (ptr native_function) function) (returns usize))
  (if (= (deref (field-pointer function 'imported)) 1)
      (wrap-cast usize 1)
      (deref (field-pointer function 'exported))))

(defun native_function_emitted_p (function)
  (declare (type (ptr native_function) function) (returns usize))
  (if (= (deref (field-pointer function 'imported)) 1)
      (deref (field-pointer function 'referenced))
      (wrap-cast usize 1)))
