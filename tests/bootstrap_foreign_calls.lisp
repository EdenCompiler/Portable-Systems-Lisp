(ffi:import-function "foreign_seven" ((a u64) (b u64) (c u64) (d u64)
                                      (e u64) (f u64) (g u64)) -> u64)

(defun local_increment (input)
  (declare (type u64 input) (returns u64))
  (wrap+ input 1))

(defun call_foreign_seven ()
  (declare (returns u64) (c-export :c))
  (ffi:call foreign_seven 1 2 3 4 5 6 (local_increment 6)))

(ffi:import-function "foreign_eight" ((a u64) (b u64) (c u64) (d u64)
                                      (e u64) (f u64) (g u64) (h u64)) -> u64)
(ffi:import-function "foreign_narrow" ((a s8) (b u16)) -> s8)
(ffi:import-function "foreign_pointer" ((input (ptr s32)) (offset usize)) -> (ptr s32))
(ffi:import-function "strlen" ((text (ptr u8))) -> usize)
(ffi:import-function "unused_foreign" () -> u64)

(defun call_foreign_eight ()
  (declare (returns u64) (c-export :c))
  (ffi:call foreign_eight 1 2 3 4 5 6 (call_foreign_seven) (local_increment 7)))

(defun call_foreign_narrow ()
  (declare (returns s64) (c-export :c))
  (wrap-cast s64 (ffi:call foreign_narrow -128 65535)))

(defun call_foreign_pointer (input)
  (declare (type (ptr s32) input) (returns s32) (c-export :c))
  (deref (ffi:call foreign_pointer input 2)))

(defun call_strlen (text)
  (declare (type (ptr u8) text) (returns usize) (c-export :c))
  (ffi:call strlen text))

(ffi:import-function "foreign_integer_zero" () -> c-int)
(ffi:import-function "foreign_pointer_zero" () -> (ptr s32))

(defun foreign_truth ()
  (declare (returns u64) (c-export :c))
  (if (ffi:call foreign_integer_zero)
      (if (ffi:call foreign_pointer_zero) 42 1)
      2))
