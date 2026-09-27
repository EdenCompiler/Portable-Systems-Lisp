(ffi:import-function "foreign_eleven"
  ((a u64) (b u64) (c u64) (d u64) (e u64) (f u64) (g u64) (h u64)
   (i s8) (j u16) (pointer (ptr s32))) -> s64)

(defun next-value (counter)
  (declare (type (ptr u64) counter) (returns u64))
  (store counter (wrap+ (deref counter) 1)))

(defun eleven_values (a b c d e f g h i j pointer)
  (declare (type u64 a b c d e f g h) (type s8 i) (type u16 j)
           (type (ptr s32) pointer) (returns s64) (c-export :c))
  (wrap+ (wrap-cast s64
           (wrap+ a (wrap+ b (wrap+ c (wrap+ d (wrap+ e (wrap+ f (wrap+ g h))))))))
    (wrap+ (wrap-cast s64 i)
      (wrap+ (wrap-cast s64 j) (wrap-cast s64 (deref pointer))))))

(defun call_eleven (counter pointer)
  (declare (type (ptr u64) counter) (type (ptr s32) pointer)
           (returns s64) (c-export :c))
  (ffi:call foreign_eleven
    (next-value counter) (next-value counter) (next-value counter) (next-value counter)
    (next-value counter) (next-value counter) (next-value counter) (next-value counter)
    -128 65535 pointer))
