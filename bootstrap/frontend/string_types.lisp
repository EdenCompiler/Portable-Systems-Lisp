;; Private frontend scratch state; decoding uses bounded stack space.
(defcstruct native_literal_scan
  (cursor usize)
  (end usize)
  (count usize)
  (output (ptr u8))
  (pending u32)
  (minimum u8)
  (maximum u8)
  (quoted u8)
  (valid u8))
