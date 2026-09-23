(ffi:import-function "sum8_c"
  ((a u64) (b u64) (c u64) (d u64)
   (e u64) (f u64) (g u64) (h u64)) -> u64)

(ffi:import-function "signed_stack_c"
  ((a u64) (b u64) (c u64) (d u64)
   (e u64) (f u64) (g s8)) -> s64)

(defun sum8_psl (a b c d e f g h)
  (declare (type u64 a b c d e f g h)
           (returns u64)
           (c-export :c))
  (wrap+ (wrap+ (wrap+ (wrap+ a b) (wrap+ c d))
                 (wrap+ e f))
         (wrap+ g h)))

(defun call_sum8_c (a b c d e f g h)
  (declare (type u64 a b c d e f g h)
           (returns u64)
           (c-export :c))
  (ffi:call sum8_c a b c d e f g h))

(defun roundtrip_signed_stack (a b c d e f g)
  (declare (type u64 a b c d e f)
           (type s8 g)
           (returns s64)
           (c-export :c))
  (ffi:call signed_stack_c a b c d e f g))
