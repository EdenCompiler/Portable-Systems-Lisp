(defcstruct triple
  (first u32)
  (second u32)
  (third u32))

(ffi:import-function "bump_triple_c" ((value triple)) -> triple)
(ffi:import-function "bump_triple_stack_c"
  ((a u64) (b u64) (c u64) (d u64) (value triple)) -> triple)

(defun roundtrip_triple (value)
  (declare (type triple value) (returns triple) (c-export :c))
  (ffi:call bump_triple_c value))

(defun roundtrip_triple_stack (a b c d value)
  (declare (type u64 a b c d)
           (type triple value)
           (returns triple)
           (c-export :c))
  (ffi:call bump_triple_stack_c a b c d value))
