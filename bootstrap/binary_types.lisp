;; Layout declarations shared by compiler code and hosted driver storage.

(defcstruct byte_buffer
  (data (ptr u8))
  (length usize)
  (capacity usize))
