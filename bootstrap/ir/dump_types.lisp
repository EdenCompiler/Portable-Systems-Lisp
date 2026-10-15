;; Caller-owned append-only text. Stage bits: HIR=1, SSA=2, LIR=4.
(defcstruct native_ir_dump
  (output (ptr byte_buffer))
  (stages u32)
  (required usize)
  (error u32)
  (cursor usize)
  (writing u8))
