(ffi:import-function "malloc" ((size usize)) -> (ptr void))
(ffi:import-function "free" ((memory (ptr void))) -> void)
(ffi:import-function "void_store_c" ((output (ptr u64)) (value u64)) -> void)
(ffi:import-function "void_seven_c" ((output (ptr u64)) (a u64) (b u64)
                                    (c u64) (d u64) (e u64) (f u64)) -> void)

(defcstruct opaque_holder (memory (ptr void)))

(defun heap_roundtrip ()
  (declare (returns u64) (c-export :c))
  (let ((memory (ffi:call malloc 8)))
    (let ((typed (ptr-cast (ptr u64) memory)))
      (store typed 42)
      (let ((answer (deref typed)))
        (ffi:call free memory)
        answer))))

(defun void_forward (output count)
  (declare (type (ptr u64) output) (type u64 count)
           (returns void) (c-export :c))
  (void_recursive output count))

(defun void_recursive (output count)
  (declare (type (ptr u64) output) (type u64 count) (returns void))
  (if (= count 0)
      (ffi:call void_store_c output 42)
      (progn
        (ffi:call void_store_c output count)
        (void_recursive output (wrap- count 1)))))

(defun void_branch (output selector)
  (declare (type (ptr u64) output) (type u64 selector)
           (returns void) (c-export :c))
  (let ((saved output))
    (if (< selector 1)
        (ffi:call void_seven_c saved 1 2 3 4 5 6)
        (ffi:call void_store_c saved 99))))

(defun void_loop (output)
  (declare (type (ptr u64) output) (returns void) (c-export :c))
  (store output 0)
  (while (< (deref output) 3)
    (ffi:call void_store_c output (wrap+ (deref output) 1)))
  (ffi:call void_store_c output (wrap+ (deref output) 39)))

(defun opaque_roundtrip (holder memory)
  (declare (type (ptr opaque_holder) holder) (type (ptr void) memory)
           (returns (ptr void)) (c-export :c))
  (store (field-pointer holder 'memory) memory)
  (deref (field-pointer holder 'memory)))

(defun opaque_truth (memory)
  (declare (type (ptr void) memory) (returns u64) (c-export :c))
  (if memory 42 0))

;; VOID locals carry completion metadata, without a value to load or copy.
(defun void_binding (output)
  (declare (type (ptr u64) output) (returns void) (c-export :c))
  (let ((done (ffi:call void_store_c output 42))) done))
