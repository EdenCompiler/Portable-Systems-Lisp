(include "win64_frame.lisp")

(defun win64_register_argument (code index)
  (declare (type (ptr byte_buffer) code) (type usize index)
           (returns c-int) (c-export :c))
  (cond
    ((= index 1) (emit_integer code #xc18948 3)) ; mov rcx, rax
    ((= index 2) (emit_integer code #xc28948 3)) ; mov rdx, rax
    ((= index 3) (emit_integer code #xc08949 3)) ; mov r8, rax
    ((= index 4) (emit_integer code #xc18949 3)) ; mov r9, rax
    (t 0)))

(defun win64_stack_argument (code index outgoing)
  (declare (type (ptr byte_buffer) code) (type usize index outgoing)
           (returns c-int) (c-export :c))
  (if (< index 5) 0
      (if (< 268435445 index) 0
          (let ((offset (wrap+ 32 (wrap* (wrap- index 5) 8))))
            (if (< outgoing (wrap+ offset 8)) 0
                (if (= (room_for code 8) 0) 0
                    (progn
                      (emit_integer code #x24848948 4) ; mov [rsp+disp32], rax
                      (emit_integer code (wrap-cast u64 offset) 4))))))))
