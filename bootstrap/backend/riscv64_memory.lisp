(include "riscv64_encode.lisp")

;; Raw source pointers may be unaligned. Assemble loads from unsigned bytes;
;; byte stores preserve the RHS in t1, which is also the store expression value.
(defun rv_load_bytes (code width index)
  (declare (type (ptr byte_buffer) code) (type usize width index) (returns c-int))
  (if (= index width) (rv_move code 5 6)
      (if (= (rv_i code #x03 28 5 4 (wrap-cast u64 index)) 0) 0
          (if (= (rv_i code #x13 28 28 1 (wrap-cast u64 (wrap* index 8))) 0) 0
              (if (= (rv_r code #x33 6 6 28 6 0) 0) 0 (rv_load_bytes code width (wrap+ index 1)))))))

(defun rv_load_memory (code width scalar_code)
  (declare (type (ptr byte_buffer) code) (type usize width) (type u32 scalar_code) (returns c-int))
  (if (= (rv_immediate code 6 0) 0) 0
      (if (= (rv_load_bytes code width 0) 0) 0 (rv_normalize code 5 scalar_code))))

(defun rv_store_bytes (code width index)
  (declare (type (ptr byte_buffer) code) (type usize width index) (returns c-int))
  (if (= index width) (rv_move code 5 6)
      (if (= (rv_i code #x13 28 6 5 (wrap-cast u64 (wrap* index 8))) 0) 0
          (if (= (rv_s code 5 28 0 (wrap-cast u64 index)) 0) 0
              (rv_store_bytes code width (wrap+ index 1))))))
