;; Minimal native x86-64 expression encoder. All instructions are written
;; directly into the object buffer; no assembler or LLVM process is involved.

(defun x86_load_immediate (code value)
  (declare (type (ptr byte_buffer) code)
           (type u64 value)
           (returns c-int))
  (if (= (room_for code 10) 0)
      0
      (progn
        (emit_byte_unchecked code #x48)
        (emit_byte_unchecked code #xb8) ; movabs rax, immediate
        (emit_integer code value 8))))

(defun x86_function_prologue (code local_count)
  (declare (type (ptr byte_buffer) code)
           (type usize local_count)
           (returns c-int))
  (if (< 268435447 local_count)
      0
      (let ((frame (wrap+ 48
                          (wrap* 8 (bits-and (wrap+ local_count 1)
                                             (wrap- 0 2))))))
        (if (= (room_for code 35) 0)
            0
            (progn
              (emit_byte_unchecked code #x55) ; push rbp
              (emit_integer code #xe58948 3) ; mov rbp, rsp
              (emit_integer code #xec8148 3) ; sub rsp, imm32
              (emit_integer code (wrap-cast u64 frame) 4)
              (emit_integer code #xf87d8948 4) ; mov [rbp-8], rdi
              (emit_integer code #xf0758948 4) ; mov [rbp-16], rsi
              (emit_integer code #xe8558948 4) ; mov [rbp-24], rdx
              (emit_integer code #xe04d8948 4) ; mov [rbp-32], rcx
              (emit_integer code #xd845894c 4) ; mov [rbp-40], r8
              (emit_integer code #xd04d894c 4)))))) ; mov [rbp-48], r9

(defun x86_local_displacement (slot)
  (declare (type usize slot) (returns u64))
  (wrap- 0 (wrap+ 48 (wrap* 8 (wrap-cast u64 slot)))))

(defun x86_store_local (code slot local_count)
  (declare (type (ptr byte_buffer) code)
           (type usize slot local_count)
           (returns c-int))
  (if (= slot 0)
      0
      (if (< local_count slot)
          0
          (if (= (room_for code 7) 0)
              0
              (progn
                (emit_integer code #x858948 3) ; mov [rbp+disp32], rax
                (emit_integer code (x86_local_displacement slot) 4))))))

(defun x86_load_local (code slot local_count)
  (declare (type (ptr byte_buffer) code)
           (type usize slot local_count)
           (returns c-int))
  (if (= slot 0)
      0
      (if (< local_count slot)
          0
          (if (= (room_for code 7) 0)
              0
              (progn
                (emit_integer code #x858b48 3) ; mov rax, [rbp+disp32]
                (emit_integer code (x86_local_displacement slot) 4))))))

(defun x86_parameter_displacement (index)
  (declare (type usize index) (returns u64))
  (if (< 6 index)
      (wrap+ 16 (wrap* 8 (wrap-cast u64 (wrap- index 7))))
      (wrap- 0 (wrap* 8 (wrap-cast u64 index)))))

(defun x86_load_parameter (code index)
  (declare (type (ptr byte_buffer) code)
           (type usize index)
           (returns c-int))
  (if (= index 0) 0
      (if (< 268435460 index) 0
          (if (= (room_for code 7) 0) 0
              (progn
                (emit_integer code #x858b48 3) ; mov rax, [rbp+disp32]
                (emit_integer code (x86_parameter_displacement index) 4))))))

(defun x86_save_left (code)
  (declare (type (ptr byte_buffer) code) (returns c-int))
  (emit_byte code #x50)) ; push rax

(defun x86_extend_unsigned (code bits)
  (declare (type (ptr byte_buffer) code) (type u32 bits) (returns c-int))
  (cond
    ((= bits 8) (emit_integer code #xc0b60f 3)) ; movzx eax, al
    ((= bits 16) (emit_integer code #xc0b70f 3)) ; movzx eax, ax
    ((= bits 32) (emit_integer code #xc089 2)) ; mov eax, eax
    ((= bits 64) 1)
    (t 0)))

(defun x86_extend_signed (code bits)
  (declare (type (ptr byte_buffer) code) (type u32 bits) (returns c-int))
  (cond
    ((= bits 8) (emit_integer code #xc0be0f48 4)) ; movsx rax, al
    ((= bits 16) (emit_integer code #xc0bf0f48 4)) ; movsx rax, ax
    ((= bits 32) (emit_integer code #xc06348 3)) ; movsxd rax, eax
    ((= bits 64) 1)
    (t 0)))

(defun x86_normalize_integer (code bits signed)
  (declare (type (ptr byte_buffer) code)
           (type u32 bits)
           (type c-int signed)
           (returns c-int))
  (if (= signed 1)
      (x86_extend_signed code bits)
      (x86_extend_unsigned code bits)))

(defun x86_arithmetic_instruction (code operation)
  (declare (type (ptr byte_buffer) code)
           (type u8 operation)
           (returns c-int))
  (if (= operation 43) ; wrap+
      (emit_integer code #xc80148 3) ; add rax, rcx
      (if (= operation 45) ; wrap-
          (progn
            (emit_integer code #xc12948 3) ; sub rcx, rax
            (emit_integer code #xc88948 3)) ; mov rax, rcx
          (if (= operation 42) ; wrap*
              (emit_integer code #xc1af0f48 4) ; imul rax, rcx
              (if (= operation 38) ; bits-and
                  (emit_integer code #xc82148 3) ; and rax, rcx
                  (if (= operation 94) ; shr64
                      (emit_integer code #xe8d3489148 5)
                      0))))))

(defun x86_combine (code operation)
  (declare (type (ptr byte_buffer) code)
           (type u8 operation)
           (returns c-int))
  (if (= (room_for code 7) 0)
      0
      (progn
        (emit_byte_unchecked code #x59) ; pop rcx (left operand)
        (x86_arithmetic_instruction code operation))))

(defun x86_return (code)
  (declare (type (ptr byte_buffer) code) (returns c-int))
  (if (= (room_for code 2) 0)
      0
      (progn
        (emit_byte_unchecked code #xc9) ; leave
        (emit_byte_unchecked code #xc3)))) ; ret

(defun x86_pop_argument (code index)
  (declare (type (ptr byte_buffer) code)
           (type usize index)
           (returns c-int))
  (if (= index 1)
      (emit_byte code #x5f) ; pop rdi
      (if (= index 2)
          (emit_byte code #x5e) ; pop rsi
          (if (= index 3)
              (emit_byte code #x5a) ; pop rdx
              (if (= index 4)
                  (emit_byte code #x59) ; pop rcx
                  (if (= index 5)
                      (emit_integer code #x5841 2) ; pop r8
                      (if (= index 6)
                          (emit_integer code #x5941 2) ; pop r9
                          0)))))))

(defun x86_scalar_operation (kind)
  (declare (type u32 kind) (returns u8))
  (if (= kind 4)
      43
      (if (= kind 5)
          45
          (if (= kind 6)
              42
              (if (= kind 11)
                  38
                  (if (= kind 12) 94 0))))))

