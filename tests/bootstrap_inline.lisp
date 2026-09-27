(ffi:import-function "inline_tick" ((state (ptr u64)) (value u64)) -> u64)

(defun inline_result (value state)
  (declare (type u64 value) (type (ptr u64) state) (returns u64) (c-export :c))
  (let ((pair (inline_pair value 3)))
    (store state pair)
    (wrap+ (inline_pair pair 4) (inline_constant))))

(defun inline_pair (left right)
  (declare (type u64 left right) (returns u64))
  (wrap+ (wrap* left 2) right))

(defun inline_constant () (declare (returns u64)) 7)

(defun inline_constant_case ()
  (declare (returns u64) (c-export :c))
  (inline_pair (inline_constant) 3))

(defun inline_order (state)
  (declare (type (ptr u64) state) (returns u64) (c-export :c))
  (inline_ignore (ffi:call inline_tick state 1) (ffi:call inline_tick state 2)))

(defun inline_ignore (left right)
  (declare (type u64 left right) (returns u64))
  42)

(defun inline_narrow (value)
  (declare (type s8 value) (returns s8) (c-export :c))
  (inline_signed (inline_signed value)))

(defun inline_signed (value)
  (declare (type s8 value) (returns s8))
  (wrap+ value 10))

(defun inline_cast (value)
  (declare (type u64 value) (returns s64) (c-export :c))
  (inline_widen value))

(defun inline_widen (value)
  (declare (type u64 value) (returns s64))
  (wrap-cast s64 (wrap-cast s8 value)))

(defun inline_pointer (value)
  (declare (type (ptr u64) value) (returns (ptr void)) (c-export :c))
  (inline_opaque value))

(defun inline_opaque (value)
  (declare (type (ptr u64) value) (returns (ptr void)))
  (ptr-cast (ptr void) value))

(defun inline_passthrough (value)
  (declare (type (ptr u64) value) (returns (ptr u64)) (c-export :c))
  (inline_identity value))

(defun inline_identity (value)
  (declare (type (ptr u64) value) (returns (ptr u64))) value)

(defun inline_many (value)
  (declare (type u64 value) (returns u64) (c-export :c))
  (inline_seven value 2 3 4 5 6 7))

(defun inline_seven (a b c d e f g)
  (declare (type u64 a b c d e f g) (returns u64))
  (wrap+ g (wrap+ a g)))

(defun inline_control (value state)
  (declare (type u64 value) (type (ptr u64) state) (returns u64) (c-export :c))
  (let ((choice (if (< value 5) (inline_pair value 1) (inline_pair value 2))))
    (store state 0)
    (while (< (deref state) 2) (store state (inline_pair (deref state) 1)))
    (wrap+ choice (deref state))))

(defun inline_memory (state)
  (declare (type (ptr u64) state) (returns u64) (c-export :c))
  (inline_load state))

(defun inline_load (state)
  (declare (type (ptr u64) state) (returns u64)) (deref state))

(defun inline_recursive (value)
  (declare (type u64 value) (returns u64) (c-export :c))
  (if (= value 0) 42 (inline_recursive (wrap- value 1))))
