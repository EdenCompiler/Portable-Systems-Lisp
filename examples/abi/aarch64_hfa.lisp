(defcstruct four-floats
  (first c-float)
  (second c-float)
  (third c-float)
  (fourth c-float))

(defcstruct float-pair
  (first c-float)
  (second c-float))

(defcstruct nested-floats
  (first float-pair)
  (second float-pair))

(ffi:import-function "bump_four_c"
  ((value four-floats)) -> four-floats)
(ffi:import-function "bump_nested_c"
  ((value nested-floats)) -> nested-floats)
(ffi:import-function "exhausted_four_c"
  ((a c-float) (b c-float) (c c-float) (d c-float)
   (e c-float) (f c-float) (g c-float) (h c-float)
   (value four-floats)) -> four-floats)

(defun pass_four (value)
  (declare (type four-floats value)
           (returns four-floats)
           (c-export :c))
  (ffi:call bump_four_c value))

(defun pass_nested (value)
  (declare (type nested-floats value)
           (returns nested-floats)
           (c-export :c))
  (ffi:call bump_nested_c value))

(defun pass_exhausted_four (a b c d e f g h value)
  (declare (type c-float a b c d e f g h)
           (type four-floats value)
           (returns four-floats)
           (c-export :c))
  (ffi:call exhausted_four_c a b c d e f g h value))
