(include "../binary.lisp")

;; SysV integer and pointer arguments beyond the sixth occupy eight-byte
;; stack slots. Padding follows the last argument, keeping rsp aligned at call.
(defun x86_stack_argument_count (arity)
  (declare (type usize arity) (returns usize))
  (if (< 6 arity) (wrap- arity 6) (wrap-cast usize 0)))

(defun x86_stack_argument_bytes (count)
  (declare (type usize count) (returns usize))
  (wrap* 8 (bits-and (wrap+ count 1) (wrap- 0 2))))

(defun x86_adjust_stack (code bytes reserve)
  (declare (type (ptr byte_buffer) code)
           (type usize bytes) (type c-int reserve) (returns c-int))
  (if (= bytes 0) 1
      (if (< 2147483647 bytes) 0
          (if (= (room_for code 7) 0) 0
              (progn
                (emit_integer code (if (= reserve 1) #xec8148 #xc48148) 3)
                (emit_integer code (wrap-cast u64 bytes) 4))))))

;; The instruction displacement is a signed 32-bit byte offset.
(defun x86_store_stack_argument (code index)
  (declare (type (ptr byte_buffer) code)
           (type usize index) (returns c-int))
  (if (< index 7) 0
      (if (< 268435461 index) 0
          (if (= (room_for code 8) 0) 0
              (progn
                (emit_integer code #x24848948 4) ; mov [rsp+disp32], rax
                (emit_integer code (wrap-cast u64 (wrap* 8 (wrap- index 7))) 4))))))
