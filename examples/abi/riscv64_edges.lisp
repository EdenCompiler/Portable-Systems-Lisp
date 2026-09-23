(defcstruct pair
  (first u64)
  (second u64))

(ffi:import-function "split_pair_c"
  ((a u64) (b u64) (c u64) (d u64) (e u64) (f u64) (g u64)
   (value pair)) -> pair)
(ffi:import-function "sum9_c"
  ((a u64) (b u64) (c u64) (d u64) (e u64)
   (f u64) (g u64) (h u64) (i u64)) -> u64)
(ffi:import-function "signed9_c"
  ((a u64) (b u64) (c u64) (d u64) (e u64)
   (f u64) (g u64) (h u64) (i s8)) -> s64)
(ffi:import-function "float9_c"
  ((a c-double) (b c-double) (c c-double) (d c-double)
   (e c-double) (f c-double) (g c-double) (h c-double)
   (i c-double)) -> c-double)

(defun split_pair (a b c d e f g value)
  (declare (type u64 a b c d e f g)
           (type pair value)
           (returns pair)
           (c-export :c))
  (ffi:call split_pair_c a b c d e f g value))

(defun sum9 (a b c d e f g h i)
  (declare (type u64 a b c d e f g h i)
           (returns u64)
           (c-export :c))
  (ffi:call sum9_c a b c d e f g h i))

(defun signed9 (a b c d e f g h i)
  (declare (type u64 a b c d e f g h)
           (type s8 i)
           (returns s64)
           (c-export :c))
  (ffi:call signed9_c a b c d e f g h i))

(defun float9 (a b c d e f g h i)
  (declare (type c-double a b c d e f g h i)
           (returns c-double)
           (c-export :c))
  (ffi:call float9_c a b c d e f g h i))
