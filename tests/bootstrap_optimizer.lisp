(ffi:import-function "optimizer_tick" ((counter (ptr u64))) -> u64)
(ffi:import-function "optimizer_null" ((counter (ptr u64))) -> (ptr void))
(ffi:import-function "optimizer_void" ((counter (ptr u64))) -> void)

(defun fold_u8 ()
  (declare (returns u8) (c-export :c))
  (wrap* (wrap+ 255 2) 7))

(defun fold_s8 ()
  (declare (returns s8) (c-export :c))
  (wrap+ 127 2))

(defun fold_u16 ()
  (declare (returns u16) (c-export :c))
  (wrap- 0 2))

(defun fold_s16 ()
  (declare (returns s16) (c-export :c))
  (wrap* 16384 2))

(defun fold_u32 ()
  (declare (returns u32) (c-export :c))
  (wrap+ 4294967295 2))

(defun fold_s32 ()
  (declare (returns c-int) (c-export :c))
  (wrap- -2147483648 1))

(defun fold_u64 ()
  (declare (returns u64) (c-export :c))
  (wrap+ 18446744073709551615 43))

(defun fold_cast ()
  (declare (returns u64) (c-export :c))
  (wrap-cast u64 (wrap-cast s8 (wrap-cast u16 511))))

(defun fold_signed_compare ()
  (declare (returns u64) (c-export :c))
  (if (< (wrap-cast s8 128) (wrap-cast s8 1)) 42 0))

(defun fold_unsigned_compare ()
  (declare (returns u64) (c-export :c))
  (if (< (wrap-cast u8 255) (wrap-cast u8 1)) 0 42))

(defun fold_equal ()
  (declare (returns u64) (c-export :c))
  (if (= (wrap-cast u8 257) (wrap-cast u8 1)) 42 0))

(defun fold_bits ()
  (declare (returns s8) (c-export :c))
  (bits-and -128 -1))

(defun fold_shift64 ()
  (declare (returns u64) (c-export :c))
  (shr64 18446744073709551615 64))

(defun fold_shift65 ()
  (declare (returns u64) (c-export :c))
  (shr64 18446744073709551615 65))

(defun fold_shiftmax ()
  (declare (returns u64) (c-export :c))
  (shr64 18446744073709551615 18446744073709551615))

(defun fold_join (choice)
  (declare (type u64 choice) (returns u64) (c-export :c))
  (wrap+ (if (= choice 0) (wrap+ 39 2) (wrap- 43 2)) 1))

(defun fold_boolean_join (choice)
  (declare (type u64 choice) (returns u64) (c-export :c))
  (if (if (= choice 0) (< (wrap-cast s8 128) (wrap-cast s8 1)) (= 1 1)) 42 0))

(defun fold_truth (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (if (ffi:call optimizer_tick counter) 42 0))

(defun fold_null_truth (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (if (ffi:call optimizer_null counter) 42 0))

(defun fold_void_effect (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (ffi:call optimizer_void counter)
  (wrap+ 40 2))

(defun fold_loop (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (store counter (wrap+ 40 2))
  (while (< (deref counter) 44)
    (store counter (wrap+ (deref counter) 1)))
  (deref counter))

(defun dead_arithmetic (input)
  (declare (type u64 input) (returns u64) (c-export :c))
  (wrap* (wrap+ input 17) (wrap- input 3))
  42)

(defun dead_join (choice counter)
  (declare (type u64 choice) (type (ptr u64) counter)
           (returns u64) (c-export :c))
  (let ((unused (if (= choice 0)
                    (wrap+ (ffi:call optimizer_tick counter) choice)
                    (wrap* (ffi:call optimizer_tick counter) choice))))
    42))

(defun dead_store (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (store counter 17)
  (wrap* (deref counter) 3)
  42)

(defun dead_void (counter)
  (declare (type (ptr u64) counter) (returns void) (c-export :c))
  (wrap* (deref counter) 3)
  (ffi:call optimizer_void counter))
