(include "riscv64_encode.lisp")

;; s0 is the entry SP (CFA). Saved s0/ra are at CFA-16/-8, incoming a0-a7
;; at CFA-24 through CFA-80, followed by eight-byte virtual-register slots.
(defun rv_frame_address (code offset negative)
  (declare (type (ptr byte_buffer) code) (type usize offset) (type c-int negative) (returns c-int))
  (if (= (rv_immediate code 7 (wrap-cast u64 offset)) 0) 0
      (rv_r code #x33 7 8 7 0 (if (= negative 1) 32 (wrap-cast u64 0)))))

(defun rv_load_frame (code register offset negative)
  (declare (type (ptr byte_buffer) code) (type u64 register) (type usize offset)
           (type c-int negative) (returns c-int))
  (if (= (rv_frame_address code offset negative) 0) 0 (rv_i code #x03 register 7 3 0)))

(defun rv_store_frame (code register offset)
  (declare (type (ptr byte_buffer) code) (type u64 register) (type usize offset) (returns c-int))
  (if (= (rv_frame_address code offset 1) 0) 0 (rv_s code 7 register 3 0)))

(defun rv_local_offset (reference)
  (declare (type usize reference) (returns usize))
  (wrap+ 80 (wrap* reference 8)))

(defun rv_adjust_stack (code bytes reserve)
  (declare (type (ptr byte_buffer) code) (type usize bytes) (type c-int reserve) (returns c-int))
  (if (= bytes 0) 1
      (if (= (rv_immediate code 7 (wrap-cast u64 bytes)) 0) 0
          (rv_r code #x33 2 2 7 0 (if (= reserve 1) 32 (wrap-cast u64 0))))))

(defun rv_save_parameters (code index)
  (declare (type (ptr byte_buffer) code) (type usize index) (returns c-int))
  (if (= index 8) 1
      (if (= (rv_store_frame code (wrap-cast u64 (wrap+ 10 index))
                             (wrap+ 24 (wrap* index 8))) 0) 0
          (rv_save_parameters code (wrap+ index 1)))))

(defun rv_function_prologue (code values)
  (declare (type (ptr byte_buffer) code) (type usize values) (returns c-int))
  (if (< 134217719 values) 0
      (if (= (rv_i code #x13 2 2 0 (wrap- 0 16)) 0) 0
          (if (= (rv_s code 2 8 3 0) 0) 0
              (if (= (rv_s code 2 1 3 8) 0) 0
                  (if (= (rv_i code #x13 8 2 0 16) 0) 0
                      (if (= (rv_adjust_stack code
                               (wrap+ 64 (wrap* 8 (bits-and (wrap+ values 1) (wrap- 0 2)))) 1) 0) 0
                          (rv_save_parameters code 0))))))))

(defun rv_load_parameter (code register index)
  (declare (type (ptr byte_buffer) code) (type u64 register) (type usize index) (returns c-int))
  (if (= index 0) 0
      (if (< 134217719 index) 0
          (if (< 8 index) (rv_load_frame code register (wrap* (wrap- index 9) 8) 0)
              (rv_load_frame code register (wrap+ 16 (wrap* index 8)) 1)))))

(defun rv_store_stack_argument (code register index)
  (declare (type (ptr byte_buffer) code) (type u64 register) (type usize index) (returns c-int))
  (if (= (rv_immediate code 7 (wrap-cast u64 (wrap* (wrap- index 9) 8))) 0) 0
      (if (= (rv_r code #x33 7 2 7 0 0) 0) 0 (rv_s code 7 register 3 0))))

(defun rv_return (code)
  (declare (type (ptr byte_buffer) code) (returns c-int))
  (if (= (rv_i code #x13 2 8 0 (wrap- 0 16)) 0) 0
      (if (= (rv_i code #x03 8 2 3 0) 0) 0
          (if (= (rv_i code #x03 1 2 3 8) 0) 0
              (if (= (rv_i code #x13 2 2 0 16) 0) 0 (rv_i code #x67 0 1 0 0))))))
