(defcstruct pair
  (first u64)
  (second u64))

(defcstruct tiny
  (value u32))

(defcstruct mixed
  (id u64)
  (weight c-double))

(defcstruct mixed-reverse
  (weight c-double)
  (id u64))

(defcstruct two-floats
  (first c-double)
  (second c-double))

(defcstruct combined
  (measure c-float)
  (count c-int))

(ffi:import-function "bump_pair_c" ((value pair)) -> pair)
(ffi:import-function "bump_tiny_c" ((value tiny)) -> tiny)
(ffi:import-function "exhausted_pair_c"
  ((a u64) (b u64) (c u64) (d u64) (e u64) (value pair)) -> pair)
(ffi:import-function "bump_mixed_c" ((value mixed)) -> mixed)
(ffi:import-function "bump_mixed_reverse_c"
  ((value mixed-reverse)) -> mixed-reverse)
(ffi:import-function "bump_two_floats_c"
  ((value two-floats)) -> two-floats)
(ffi:import-function "bump_combined_c"
  ((value combined)) -> combined)
(ffi:import-function "exhausted_mixed_c"
  ((a c-double) (b c-double) (c c-double) (d c-double)
   (e c-double) (f c-double) (g c-double) (h c-double)
   (value mixed)) -> mixed)

(defun pass_pair (value)
  (declare (type pair value) (returns pair) (c-export :c))
  (ffi:call bump_pair_c value))

(defun pass_tiny (value)
  (declare (type tiny value) (returns tiny) (c-export :c))
  (ffi:call bump_tiny_c value))

(defun roundtrip_exhausted (a b c d e value)
  (declare (type u64 a b c d e)
           (type pair value)
           (returns pair)
           (c-export :c))
  (ffi:call exhausted_pair_c a b c d e value))

(defun pass_mixed (value)
  (declare (type mixed value) (returns mixed) (c-export :c))
  (ffi:call bump_mixed_c value))

(defun pass_mixed_reverse (value)
  (declare (type mixed-reverse value)
           (returns mixed-reverse)
           (c-export :c))
  (ffi:call bump_mixed_reverse_c value))

(defun pass_two_floats (value)
  (declare (type two-floats value)
           (returns two-floats)
           (c-export :c))
  (ffi:call bump_two_floats_c value))

(defun pass_combined (value)
  (declare (type combined value)
           (returns combined)
           (c-export :c))
  (ffi:call bump_combined_c value))

(defun roundtrip_exhausted_mixed (a b c d e f g h value)
  (declare (type c-double a b c d e f g h)
           (type mixed value)
           (returns mixed)
           (c-export :c))
  (ffi:call exhausted_mixed_c a b c d e f g h value))
