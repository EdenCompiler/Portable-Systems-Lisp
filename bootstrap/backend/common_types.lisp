;; Layout declarations shared by compiler code and hosted driver storage.

(defcstruct native_function
  (name (ptr u8))
  (name_length usize)
  (offset usize)
  (size usize)
  (arity usize)
  (exported usize)
  (imported usize)
  (referenced usize))
