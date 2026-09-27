;; Function descriptors are supplied in source order. Their code spans must
;; partition the .text bytes. Imports have zero spans and become undefined
;; symbols only when referenced. Names are ASCII slices of caller-owned source.
(defcstruct native_function
  (name (ptr u8))
  (name_length usize)
  (offset usize)
  (size usize)
  (arity usize)
  (exported usize)
  (imported usize)
  (referenced usize))

(defun native_function_at (functions index)
  (declare (type (ptr native_function) functions)
           (type usize index)
           (returns (ptr native_function)))
  (pointer+ functions (wrap-cast isize index)))


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
