(defun add (a b)
  (declare (type u64 a b)
           (returns u64)
           (c-export :c))
  (wrap+ a b))

(ffi:import-function "multiply_c" ((a u64) (b u64)) -> u64)

(defun add_then_multiply (a b)
  (declare (type u64 a b)
           (returns u64)
           (c-export :c))
  (ffi:call multiply_c (add a b) 3))

(defmacro twice (value)
  `(wrap+ ,value ,value))

(defun choose_and_double (a b)
  (declare (type u64 a b)
           (returns u64)
           (c-export :c))
  (let ((larger (if (< a b) b a)))
    (twice larger)))

(defun subtract (a b)
  (declare (type u64 a b)
           (returns u64)
           (c-export :c))
  (wrap- a b))

(defun signed_min (a b)
  (declare (type s64 a b)
           (returns s64)
           (c-export :c))
  (if (< a b) a b))

(defun zero_is_true ()
  (declare (returns u64) (c-export :c))
  (if 0 42 0))

(defun nil_is_false ()
  (declare (returns u64) (c-export :c))
  (if nil 0 (wrap* 6 7)))

(defun nested_choice (a b)
  (declare (type u64 a b)
           (returns u64)
           (c-export :c))
  (if (< a b)
      (if (= b 21) 42 0)
      0))

(defun let_is_parallel (x)
  (declare (type u64 x)
           (returns u64)
           (c-export :c))
  (let ((x 1) (y x))
    (wrap+ x y)))

; A UTF-8 comment and a Common Lisp radix literal are both read on the host.
; comentário de compilação
(defun reader_radix ()
  (declare (returns u64) (c-export :c))
  #x2a)
