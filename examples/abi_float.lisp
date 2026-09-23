(ffi:import-function "mix_c"
  ((a c-long) (b c-double) (c c-float) (d c-long)) -> c-double)

(ffi:import-function "sum9_c"
  ((a c-double) (b c-double) (c c-double)
   (d c-double) (e c-double) (f c-double)
   (g c-double) (h c-double) (i c-double)) -> c-double)

(defun pass_mix (a b c d)
  (declare (type c-long a d)
           (type c-double b)
           (type c-float c)
           (returns c-double)
           (c-export :c))
  (ffi:call mix_c a b c d))

(defun pass_nine_floats (a b c d e f g h i)
  (declare (type c-double a b c d e f g h i)
           (returns c-double)
           (c-export :c))
  (ffi:call sum9_c a b c d e f g h i))

(defun float_constant ()
  (declare (returns c-float) (c-export :c))
  1.25f0)

(defun double_constant ()
  (declare (returns c-double) (c-export :c))
  3.5d0)
