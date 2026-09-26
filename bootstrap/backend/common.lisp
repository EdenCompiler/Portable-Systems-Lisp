;; Function descriptors are supplied in source order. Their code spans must
;; partition the .text bytes; names are ASCII slices of caller-owned source.
(defcstruct native_function
  (name (ptr u8))
  (name_length usize)
  (offset usize)
  (size usize)
  (arity usize)
  (exported usize))

(defun native_function_at (functions index)
  (declare (type (ptr native_function) functions)
           (type usize index)
           (returns (ptr native_function)))
  (pointer+ functions (wrap-cast isize index)))

