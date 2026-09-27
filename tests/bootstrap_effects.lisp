(ffi:import-function "effect_tick" ((counter (ptr u64))) -> u64 :no-allocation)
(ffi:import-function "effect_unknown" ((counter (ptr u64))) -> u64)
(ffi:import-function "effect_void" ((counter (ptr u64))) -> void :no-allocation)
(ffi:import-function "effect_pointer" ((counter (ptr u64))) -> (ptr u64) :no-allocation)

(defun effect_region (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (without-allocation
    (let ((value (effect_forward 5)))
      (store counter value)
      (ffi:call effect_tick counter))))

(defun effect_forward (value)
  (declare (type u64 value) (returns u64))
  (effect_even value))

(defun effect_even (value)
  (declare (type u64 value) (returns u64))
  (if (= value 0) 42 (effect_odd (wrap- value 1))))

(defun effect_odd (value)
  (declare (type u64 value) (returns u64))
  (if (= value 0) 42 (effect_even (wrap- value 1))))

(defun effect_outer_binding (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (let ((value (ffi:call effect_unknown counter)))
    (without-allocation value)))

(defun effect_loop (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (without-allocation
    (store counter 0)
    (while (< (deref counter) 3) (store counter (wrap+ (deref counter) 1)))
    (deref counter)))

(defun effect_void_case (counter)
  (declare (type (ptr u64) counter) (returns void) (c-export :c))
  (without-allocation (if nil (ffi:call effect_void counter) (ffi:call effect_void counter))))

(defun effect_pointer_case (counter)
  (declare (type (ptr u64) counter) (returns (ptr u64)) (c-export :c))
  (without-allocation (ffi:call effect_pointer counter)))

(defun effect_nested (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (without-allocation
    (without-allocation (ffi:call effect_tick counter))
    (wrap+ (deref counter) 1)))

(defun effect_discarded (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (without-allocation (ffi:call effect_tick counter))
  42)
