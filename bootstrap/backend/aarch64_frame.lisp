(include "aarch64_encode.lisp")

;; FP points at the saved FP/LR pair. Eight incoming GP registers occupy
;; FP-8 through FP-64, followed by eight saved FP payloads and virtual slots.
(defun a64_frame_address (code offset negative)
  (declare (type (ptr byte_buffer) code) (type usize offset) (type c-int negative) (returns c-int))
  (if (= (a64_immediate code 16 (wrap-cast u64 offset)) 0) 0
      (a64_register_op code (if (= negative 1) #xcb000000 #x8b000000) 16 29 16)))

(defun a64_load_frame (code register offset negative)
  (declare (type (ptr byte_buffer) code) (type u64 register) (type usize offset)
           (type c-int negative) (returns c-int))
  (if (= (a64_frame_address code offset negative) 0) 0
      (a64_memory code 8 0 0 register 16)))

(defun a64_store_frame (code register offset)
  (declare (type (ptr byte_buffer) code) (type u64 register) (type usize offset) (returns c-int))
  (if (= (a64_frame_address code offset 1) 0) 0 (a64_memory code 8 0 1 register 16)))

(defun a64_local_offset (reference)
  (declare (type usize reference) (returns usize))
  (wrap+ 128 (wrap* reference 8)))

(defun a64_adjust_stack (code bytes reserve)
  (declare (type (ptr byte_buffer) code) (type usize bytes) (type c-int reserve) (returns c-int))
  (if (= bytes 0) 1
      (let ((chunk (if (< 4080 bytes) (wrap-cast usize 4080) bytes)))
        (if (= (a64_word code (wrap+ (if (= reserve 1) #xd10003ff #x910003ff)
                                     (wrap* (wrap-cast u64 chunk) 1024))) 0) 0
            (a64_adjust_stack code (wrap- bytes chunk) reserve)))))

(defun a64_save_parameters (code index)
  (declare (type (ptr byte_buffer) code) (type usize index) (returns c-int))
  (if (= index 8) 1
      (if (= (a64_store_frame code (wrap-cast u64 index) (wrap* (wrap+ index 1) 8)) 0) 0
          (a64_save_parameters code (wrap+ index 1)))))

(defun a64_float_to_general (code general floating scalar_code)
  (declare (type (ptr byte_buffer) code) (type usize general floating)
           (type u32 scalar_code) (returns c-int))
  (a64_word code (wrap+ (if (= scalar_code 13) #x1e260000 #x9e660000)
                    (wrap+ (wrap-cast u64 general)
                           (wrap* (wrap-cast u64 floating) 32)))))

(defun a64_general_to_float (code floating general scalar_code)
  (declare (type (ptr byte_buffer) code) (type usize floating general)
           (type u32 scalar_code) (returns c-int))
  (a64_word code (wrap+ (if (= scalar_code 13) #x1e270000 #x9e670000)
                    (wrap+ (wrap-cast u64 floating)
                           (wrap* (wrap-cast u64 general) 32)))))

(defun a64_save_float_parameters (code index)
  (declare (type (ptr byte_buffer) code) (type usize index) (returns c-int))
  (if (= index 8) 1
      (if (= (a64_float_to_general code 9 index 14) 0) 0
          (if (= (a64_store_frame code 9 (wrap+ 72 (wrap* index 8))) 0) 0
              (a64_save_float_parameters code (wrap+ index 1))))))

(defun a64_function_prologue (code values)
  (declare (type (ptr byte_buffer) code) (type usize values) (returns c-int))
  ;; Bound the slot product before rounding the frame to sixteen bytes.
  (if (< 134217719 values) 0
      (let ((frame (wrap+ 128 (wrap* 8 (bits-and (wrap+ values 1) (wrap- 0 2))))))
        (if (= (a64_word code #xa9bf7bfd) 0) 0
            (if (= (a64_word code #x910003fd) 0) 0
                (if (= (a64_adjust_stack code frame 1) 0) 0
                    (if (= (a64_save_parameters code 0) 0) 0
                        1)))))))

(defun a64_load_parameter (code register index)
  (declare (type (ptr byte_buffer) code) (type u64 register) (type usize index) (returns c-int))
  (if (= index 0) 0
      (if (< 134217719 index) 0
          (if (< 8 index)
              (a64_load_frame code register (wrap+ 16 (wrap* (wrap- index 9) 8)) 0)
              (a64_load_frame code register (wrap* index 8) 1)))))

(defun a64_stack_address (code offset)
  (declare (type (ptr byte_buffer) code) (type usize offset) (returns c-int))
  (if (= (a64_immediate code 17 (wrap-cast u64 offset)) 0) 0
      (if (= (a64_word code #x910003f0) 0) 0 (a64_register_op code #x8b000000 16 16 17))))

(defun a64_store_stack_argument (code register index)
  (declare (type (ptr byte_buffer) code) (type u64 register) (type usize index) (returns c-int))
  (if (= (a64_stack_address code (wrap* (wrap- index 9) 8)) 0) 0
      (a64_memory code 8 0 1 register 16)))

(defun a64_return (code)
  (declare (type (ptr byte_buffer) code) (returns c-int))
  (if (= (a64_word code #x910003bf) 0) 0
      (if (= (a64_word code #xa8c17bfd) 0) 0 (a64_word code #xd65f03c0))))
