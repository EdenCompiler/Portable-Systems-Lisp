;; ADR anchors at its own PC. A fixed MOVZ/MOVK sequence permits a full-width
;; same-text delta rather than imposing ADR's one-megabyte reach on a unit.
(defun a64_function_delta_base (half)
  (declare (type usize half) (returns u64))
  (if (= half 0) #xd280000a
      (wrap+ #xf280000a (wrap* (wrap-cast u64 half) #x200000))))

(defun a64_encode_function_delta (code half)
  (declare (type (ptr byte_buffer) code) (type usize half) (returns c-int))
  (if (= half 4) (a64_word code #x8b0a0129)
      (if (= (a64_word code (a64_function_delta_base half)) 0) 0
          (a64_encode_function_delta code (wrap+ half 1)))))

(defun a64_encode_function_address (code)
  (declare (type (ptr byte_buffer) code) (returns c-int))
  (if (= (a64_word code #x10000009) 0) 0 (a64_encode_function_delta code 0)))

(defun a64_function_delta_shape_p (code anchor half)
  (declare (type (ptr byte_buffer) code) (type usize anchor half) (returns c-int))
  (if (= half 4) 1
      (if (= (bits-and (native_function_address_read_word code (wrap+ anchor (wrap* (wrap+ half 1) 4)))
                       #xffe0001f) (a64_function_delta_base half))
          (a64_function_delta_shape_p code anchor (wrap+ half 1)) 0)))

(defun a64_function_address_shape_p (code anchor)
  (declare (type (ptr byte_buffer) code) (type usize anchor) (returns c-int))
  (if (= (native_function_address_read_word code anchor) #x10000009)
      (if (= (native_function_address_read_word code (wrap+ anchor 20)) #x8b0a0129)
          (a64_function_delta_shape_p code anchor 0) 0) 0))

(defun a64_patch_function_delta (code anchor delta half)
  (declare (type (ptr byte_buffer) code) (type usize anchor half) (type u64 delta) (returns c-int))
  (if (= half 4) 1
      (let ((piece (bits-and (shr64 delta (wrap* (wrap-cast u64 half) 16)) 65535)))
        (if (= (patch_i32 code (wrap+ anchor (wrap* (wrap+ half 1) 4))
                 (wrap-cast s32 (wrap+ (a64_function_delta_base half) (wrap* piece 32)))) 0) 0
            (a64_patch_function_delta code anchor delta (wrap+ half 1))))))

(defun a64_patch_function_address (code anchor destination)
  (declare (type (ptr byte_buffer) code) (type usize anchor destination) (returns c-int))
  (a64_patch_function_delta code anchor (wrap-cast u64 (wrap- destination anchor)) 0))
