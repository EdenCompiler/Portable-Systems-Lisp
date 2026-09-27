(ffi:import-function "cfg_live" ((counter (ptr u64))) -> u64)
(ffi:import-function "cfg_dead" ((counter (ptr u64))) -> u64)
(ffi:import-function "cfg_void" ((counter (ptr u64))) -> void)

(defun prune_true (input counter)
  (declare (type u64 input) (type (ptr u64) counter) (returns u64) (c-export :c))
  (if t (wrap+ input 1) (ffi:call cfg_dead counter)))

(defun prune_false (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (if nil (ffi:call cfg_dead counter) (ffi:call cfg_live counter)))

(defun prune_signed (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (if (< (wrap-cast s8 128) (wrap-cast s8 1))
      (ffi:call cfg_live counter) (ffi:call cfg_dead counter)))

(defun prune_nested (input counter)
  (declare (type u64 input) (type (ptr u64) counter) (returns u64) (c-export :c))
  (let ((picked (if (= 2 2) (wrap+ input 1) (ffi:call cfg_dead counter))))
    (if (= picked 42) 7 (wrap+ picked 1))))

(defun prune_cascade (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (if (= (if nil 1 42) 42)
      (ffi:call cfg_live counter) (ffi:call cfg_dead counter)))

(defun prune_pointer (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (deref (if nil (ptr-from-address (ptr u64) 0) counter)))

(defun prune_boolean (input counter)
  (declare (type u64 input) (type (ptr u64) counter) (returns u64) (c-export :c))
  (if (if t (= input 1) (< 1 2))
      (ffi:call cfg_live counter) (wrap+ input 3)))

(defun prune_loop (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (while nil (ffi:call cfg_dead counter))
  42)

(defun prune_void (counter)
  (declare (type (ptr u64) counter) (returns void) (c-export :c))
  (if nil
      (progn (ffi:call cfg_dead counter) (ffi:call cfg_void counter))
      (ffi:call cfg_void counter)))

;; Compile this cycle without executing it: its exit and return are unreachable.
(defun prune_forever (counter)
  (declare (type (ptr u64) counter) (returns void) (c-export :c))
  (while t (ffi:call cfg_void counter))
  (ffi:call cfg_dead counter)
  (ffi:call cfg_void counter))
