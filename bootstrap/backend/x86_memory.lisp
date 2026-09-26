;; x86-64 memory instructions. Addresses use RAX; stores use RCX as the
;; address so RAX preserves the Lisp STORE expression's result.

(defun x86_load_unsigned (code width)
  (declare (type (ptr byte_buffer) code)
           (type usize width) (returns c-int))
  (cond
    ((= width 1) (emit_integer code #x00b60f 3)) ; movzx eax, byte [rax]
    ((= width 2) (emit_integer code #x00b70f 3)) ; movzx eax, word [rax]
    ((= width 4) (emit_integer code #x008b 2)) ; mov eax, [rax]
    ((= width 8) (emit_integer code #x008b48 3)) ; mov rax, [rax]
    (t 0)))

(defun x86_load_signed (code width)
  (declare (type (ptr byte_buffer) code)
           (type usize width) (returns c-int))
  (cond
    ((= width 1) (emit_integer code #x00be0f48 4)) ; movsx rax, byte [rax]
    ((= width 2) (emit_integer code #x00bf0f48 4)) ; movsx rax, word [rax]
    ((= width 4) (emit_integer code #x006348 3)) ; movsxd rax, dword [rax]
    ((= width 8) (emit_integer code #x008b48 3)) ; mov rax, [rax]
    (t 0)))

(defun x86_store_word (code width)
  (declare (type (ptr byte_buffer) code)
           (type usize width) (returns c-int))
  (cond
    ((= width 1) (emit_integer code #x0188 2)) ; mov [rcx], al
    ((= width 2) (emit_integer code #x018966 3)) ; mov [rcx], ax
    ((= width 4) (emit_integer code #x0189 2)) ; mov [rcx], eax
    ((= width 8) (emit_integer code #x018948 3)) ; mov [rcx], rax
    (t 0)))

(defun x86_scale_offset (code size)
  (declare (type (ptr byte_buffer) code)
           (type usize size) (returns c-int))
  (if (= size 1) 1
      (if (= (room_for code 14) 0) 0
          (progn
            (emit_integer code #xb948 2) ; mov rcx, imm64
            (emit_integer code (wrap-cast u64 size) 8)
            (emit_integer code #xc1af0f48 4))))) ; imul rax, rcx

(defun x86_add_field_offset (code offset)
  (declare (type (ptr byte_buffer) code)
           (type u64 offset) (returns c-int))
  (if (= offset 0) 1
      (if (= (room_for code 13) 0) 0
          (progn
            (emit_integer code #xb948 2) ; mov rcx, imm64
            (emit_integer code offset 8)
            (emit_integer code #xc80148 3))))) ; add rax, rcx
