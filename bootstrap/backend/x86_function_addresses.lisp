;; Same-text function addresses are independent of ELF/COFF symbol relocation.
;; RAX is the compiler's scalar working register on both x86-64 ABIs.
(defun x86_encode_function_address (code)
  (declare (type (ptr byte_buffer) code) (returns c-int))
  (if (= (emit_integer code #x058d48 3) 0) 0 (emit_integer code 0 4)))

(defun x86_function_address_shape_p (code offset)
  (declare (type (ptr byte_buffer) code) (type usize offset) (returns c-int))
  (if (= (bits-and (native_function_address_read_word code offset) #xffffff) #x058d48) 1 0))

(defun x86_function_address_range_p (destination anchor)
  (declare (type usize destination anchor) (returns c-int))
  (let ((next (wrap+ anchor 7)))
    (if (< destination next)
        (if (< 2147483648 (wrap- next destination)) 0 1)
        (if (< 2147483647 (wrap- destination next)) 0 1))))

(defun x86_patch_function_address (code anchor destination)
  (declare (type (ptr byte_buffer) code) (type usize anchor destination) (returns c-int))
  (patch_i32 code (wrap+ anchor 3)
    (wrap-cast s32 (wrap- destination (wrap+ anchor 7)))))
