(include "../binary.lisp")

;; Unsigned comparisons and branch displacements for verified scalar HIR.

(defun x86_compare_integer (code kind signed)
  (declare (type (ptr byte_buffer) code)
           (type u32 kind)
           (type c-int signed)
           (returns c-int))
  (if (= (room_for code 10) 0)
      0
      (progn
        (emit_byte_unchecked code #x59) ; pop rcx: left operand
        (emit_integer code #xc13948 3) ; cmp rcx, rax
        (if (= kind 8)
            (emit_integer code #xc0940f 3) ; sete al
            (if (= signed 1)
                (emit_integer code #xc09c0f 3) ; setl al
                (emit_integer code #xc0920f 3))) ; setb al
        (emit_integer code #xc0b60f 3)))) ; movzx eax, al

(defun x86_jump_if_zero_placeholder (code)
  (declare (type (ptr byte_buffer) code) (returns usize))
  (if (= (room_for code 9) 0)
      0
      (let ((jump (wrap+ (deref (field-pointer code 'length)) 3)))
        (emit_integer code #xc08548 3) ; test rax, rax
        (emit_integer code #x840f 2) ; je rel32
        (emit_integer code 0 4)
        jump)))

(defun x86_jump_placeholder (code)
  (declare (type (ptr byte_buffer) code) (returns usize))
  (if (= (room_for code 5) 0)
      0
      (let ((jump (deref (field-pointer code 'length))))
        (emit_byte_unchecked code #xe9) ; jmp rel32
        (emit_integer code 0 4)
        jump)))

(defun x86_patch_zero_jump (code jump target)
  (declare (type (ptr byte_buffer) code)
           (type usize jump target)
           (returns c-int))
  (patch_i32 code (wrap+ jump 2)
             (wrap-cast s32 (wrap- target (wrap+ jump 6)))))

(defun x86_patch_jump (code jump target)
  (declare (type (ptr byte_buffer) code)
           (type usize jump target)
           (returns c-int))
  (patch_i32 code (wrap+ jump 1)
             (wrap-cast s32 (wrap- target (wrap+ jump 5)))))
