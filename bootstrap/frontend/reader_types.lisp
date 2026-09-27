;; Layout declarations shared by compiler code and hosted driver storage.

(defcstruct psl_scanner
  (data (ptr u8))
  (length usize)
  (cursor usize)
  (error u8))

(defcstruct psl_token
  (kind u32)
  (start usize)
  (length usize))
