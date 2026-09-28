;; Static object data shared by the native ELF and COFF writers.
(defcstruct native_data_symbol
  (name (ptr u8))
  (name_length usize)
  (bytes (ptr u8))
  (size usize)
  (alignment usize)
  (exported u8))
