;; The native writer does not emit RELAX for these fixed same-text locations.
;; AUIPC/ADDI computes a defined function address in T0, the working register.
(defun rv_encode_function_address (code)
  (declare (type (ptr byte_buffer) code) (returns c-int))
  (if (= (rv_word code #x00000297) 0) 0 (rv_word code #x00028293)))

(defun rv_function_address_shape_p (code anchor)
  (declare (type (ptr byte_buffer) code) (type usize anchor) (returns c-int))
  (if (= (bits-and (native_function_address_read_word code anchor) #xfff) #x297)
      (if (= (bits-and (native_function_address_read_word code (wrap+ anchor 4)) #xfffff) #x28293) 1 0) 0))

(defun rv_function_address_range_p (destination anchor)
  (declare (type usize destination anchor) (returns c-int))
  ;; Rounding the high twenty bits removes the final 2 KiB of positive reach.
  (if (< destination anchor)
      (if (< 2147483648 (wrap- anchor destination)) 0 1)
      (if (< 2147481599 (wrap- destination anchor)) 0 1)))

(defun rv_patch_function_address (code anchor destination)
  (declare (type (ptr byte_buffer) code) (type usize anchor destination) (returns c-int))
  (let ((delta (wrap-cast u64 (wrap- destination anchor))))
    (let ((high (bits-and (wrap+ delta 2048) #xfffff000)))
      (if (= (patch_i32 code anchor (wrap-cast s32 (wrap+ high #x297))) 0) 0
          (patch_i32 code (wrap+ anchor 4)
            (wrap-cast s32 (rv_i_word #x13 5 5 0 delta)))))))
