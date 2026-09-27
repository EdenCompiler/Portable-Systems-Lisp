;; CPU-independent storage for deferred calls and local label references.
(defcstruct native_call_fixup
  (instruction usize)
  (target usize))

(defcstruct native_fixup_arena
  (items (ptr native_call_fixup))
  (count usize)
  (capacity usize)
  (error u32))
