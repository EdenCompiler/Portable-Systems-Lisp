;; Layout declarations shared by compiler code and hosted driver storage.

(defcstruct psl_parsed_integer
  (magnitude u64)
  (negative u8)
  (radix u8))
