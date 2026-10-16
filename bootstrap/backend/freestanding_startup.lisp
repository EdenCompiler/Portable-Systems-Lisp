(defun native_startup_find_main (context index count)
  (declare (type (ptr native_compile_context) context) (type usize index count)
           (returns usize))
  (let ((functions (deref (field-pointer context 'functions))))
    (store (field-pointer context 'fold_cursor) index)
    (store (field-pointer context 'inline_cursor) 0)
    (while (if (= (deref (field-pointer context 'inline_cursor)) 0)
               (< (deref (field-pointer context 'fold_cursor)) count) nil)
      (let ((function (native_function_at functions
                                          (deref (field-pointer context 'fold_cursor)))))
        (if (if (= (deref (field-pointer function 'name_length)) 4)
                (= (same_name_bytes_p (deref (field-pointer function 'name))
                                      (ffi:c-string "main") 4) 1)
                nil)
            (if (if (= (deref (field-pointer function 'imported)) 0)
                    (= (deref (field-pointer function 'arity)) 0)
                    nil)
                (if (= (deref (field-pointer function 'exported)) 1)
                    (store (field-pointer context 'inline_cursor)
                           (wrap+ (deref (field-pointer context 'fold_cursor)) 1))
                    (wrap-cast usize 1))
                (wrap-cast usize 1))
            (wrap-cast usize 1)))
      (if (= (deref (field-pointer context 'inline_cursor)) 0)
          (store (field-pointer context 'fold_cursor)
                 (wrap+ (deref (field-pointer context 'fold_cursor)) 1))
          (wrap-cast usize 1)))
    (deref (field-pointer context 'inline_cursor))))

(defun native_startup_emit_x86 (context main)
  (declare (type (ptr native_compile_context) context) (type usize main)
           (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (fixups (deref (field-pointer context 'fixups))))
    (if (= (emit_integer code #x00ed3148 3) 0) 0
        (let ((call (deref (field-pointer code 'length))))
          (if (= (emit_byte code #xe8) 0) 0
              (if (= (emit_integer code 0 4) 0) 0
                  (if (= (record_call_fixup fixups call main) 0) 0
                  (if (= (emit_integer code #xc789 2) 0) 0
                      (if (= (emit_integer code #x00003cb8 5) 0) 0
                          (if (= (emit_integer code #x050f 2) 0) 0
                              (emit_integer code #xf4 1)))))))))))

(defun native_startup_branch_word (left right funct3 delta)
  (declare (type u64 left right funct3 delta) (returns u64))
  (let ((bits (wrap-cast u64 delta)))
    (wrap+ #x63
      (wrap+ (wrap* left 32768)
        (wrap+ (wrap* right 1048576)
          (wrap+ (wrap* funct3 4096)
            (wrap+ (wrap* (bits-and (shr64 bits 12) 1) 2147483648)
              (wrap+ (wrap* (bits-and (shr64 bits 5) 63) 33554432)
                (wrap+ (wrap* (bits-and (shr64 bits 1) 15) 256)
                       (wrap* (bits-and (shr64 bits 11) 1) 128))))))))))

(defun native_startup_jump_word (destination delta)
  (declare (type u64 destination delta) (returns u64))
  (let ((bits (wrap-cast u64 delta)))
    (wrap+ #x6f
      (wrap+ (wrap* destination 128)
        (wrap+ (wrap* (bits-and (shr64 bits 12) 255) 4096)
          (wrap+ (wrap* (bits-and (shr64 bits 11) 1) 1048576)
            (wrap+ (wrap* (bits-and (shr64 bits 1) 1023) 2097152)
                   (wrap* (bits-and (shr64 bits 20) 1) 2147483648))))))))

(defun native_startup_emit_riscv (context main)
  (declare (type (ptr native_compile_context) context) (type usize main)
           (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (fixups (deref (field-pointer context 'fixups))))
    (if (= (rv_immediate code 2 #x88000000) 0) 0
        (let ((call (deref (field-pointer code 'length))))
          (if (= (record_call_fixup fixups call main) 0) 0
              (if (= (rv_word code #x97) 0) 0
                  (if (= (rv_word code #x80e7) 0) 0
                      (let ((branch (deref (field-pointer code 'length))))
                        (if (= (rv_word code 0) 0) 0
                            (if (= (rv_immediate code 5 #x5555) 0) 0
                                (let ((jump (deref (field-pointer code 'length))))
                                  (if (= (rv_word code 0) 0) 0
                                      (let ((failure (deref (field-pointer code 'length))))
                                        (if (= (rv_immediate code 5 #x13333) 0) 0
                                            (let ((write (deref (field-pointer code 'length))))
                                              (if (= (rv_immediate code 6 #x100000) 0) 0
                                                  (if (= (rv_s code 6 5 2 0) 0) 0
                                                      (if (= (rv_word code #x10500073) 0) 0
                                                          (if (= (rv_word code #xffdff06f) 0) 0
                                                              (if (= (patch_i32 code branch
                                                                   (wrap-cast s32
                                                                     (native_startup_branch_word
                                                                      (wrap-cast u64 10)
                                                                      (wrap-cast u64 0)
                                                                      (wrap-cast u64 1)
                                                                      (wrap-cast u64 (wrap- failure branch))))) 0) 0
                                                                  (if (= (patch_i32 code jump
                                                                       (wrap-cast s32
                                                                         (native_startup_jump_word
                                                                          (wrap-cast u64 0)
                                                                          (wrap-cast u64 (wrap- write jump))))) 0) 0 1)))))))))))))))))))))

(defun native_append_freestanding_startup (context count)
  (declare (type (ptr native_compile_context) context) (type usize count)
           (returns c-int))
  (let ((kind (deref (field-pointer context 'startup_kind)))
        (target (deref (field-pointer context 'target)))
        (code (deref (field-pointer context 'code)))
        (functions (deref (field-pointer context 'functions)))
        (signatures (deref (field-pointer context 'signatures))))
    (if (= kind 0) 1
        (native_startup_profile_gate context kind target count code
                                     functions signatures))))

(defun native_startup_profile_gate (context kind target count code
                                    functions signatures)
  (declare (type (ptr native_compile_context) context)
           (type u32 kind target) (type usize count)
           (type (ptr byte_buffer) code)
           (type (ptr native_function) functions)
           (type (ptr native_signature_context) signatures)
           (returns c-int))
  (if (= (deref (field-pointer context 'profile)) 0)
      (native_startup_capacity_gate context kind target count code
                                    functions signatures)
      0))

(defun native_startup_capacity_gate (context kind target count code
                                     functions signatures)
  (declare (type (ptr native_compile_context) context)
           (type u32 kind target) (type usize count)
           (type (ptr byte_buffer) code)
           (type (ptr native_function) functions)
           (type (ptr native_signature_context) signatures)
           (returns c-int))
  (if (< count (deref (field-pointer signatures 'signature_capacity)))
      (native_startup_main_gate context kind target count code functions)
      0))

(defun native_startup_main_gate (context kind target count code functions)
  (declare (type (ptr native_compile_context) context)
           (type u32 kind target) (type usize count)
           (type (ptr byte_buffer) code)
           (type (ptr native_function) functions)
           (returns c-int))
  (let ((main (native_startup_find_main context 0 count)))
    (if (= main 0) 0
        (native_startup_emit_function context kind target count code
                                      functions main))))

(defun native_startup_emit_function (context kind target count code
                                     functions main)
  (declare (type (ptr native_compile_context) context)
           (type u32 kind target) (type usize count main)
           (type (ptr byte_buffer) code)
           (type (ptr native_function) functions)
           (returns c-int))
  (let ((function (native_function_at functions count))
        (start (deref (field-pointer code 'length))))
    (native_startup_initialize_function function start)
    (native_startup_emit_target context kind target function code start main)))

(defun native_startup_initialize_function (function start)
  (declare (type (ptr native_function) function) (type usize start)
           (returns c-int))
  (store (field-pointer function 'name) (ffi:c-string "_start"))
  (store (field-pointer function 'name_length) 6)
  (store (field-pointer function 'offset) start)
  (store (field-pointer function 'arity) 0)
  (store (field-pointer function 'exported) 1)
  (store (field-pointer function 'imported) 0)
  (store (field-pointer function 'referenced) 0)
  (store (field-pointer function 'frame_size) 0)
  (store (field-pointer function 'prologue_size) 0)
  1)

(defun native_startup_emit_target (context kind target function code start main)
  (declare (type (ptr native_compile_context) context)
           (type u32 kind target) (type (ptr native_function) function)
           (type (ptr byte_buffer) code) (type usize start main)
           (returns c-int))
  (if (= kind 1)
      (if (= target 4)
          (if (= (native_startup_emit_x86 context main) 0) 0
              (native_startup_finish function code start)) 0)
      (if (= kind 2)
          (if (= target 5)
              (if (= (native_startup_emit_riscv context main) 0) 0
                  (native_startup_finish function code start)) 0)
          0)))

(defun native_startup_finish (function code start)
  (declare (type (ptr native_function) function) (type (ptr byte_buffer) code)
           (type usize start) (returns c-int))
  (store (field-pointer function 'size)
         (wrap- (deref (field-pointer code 'length)) start))
  (if (< 0 (deref (field-pointer function 'size))) 1 0))

;; A QEMU virt reset stub enters the beginning of the first load segment. Keep
;; generated startup at byte zero and in the first function slot for both none
;; targets. Rotating code preserves byte spans without allocating scratch space.
(defun native_startup_swap_bytes (code left right)
  (declare (type (ptr byte_buffer) code) (type usize left right)
           (returns c-int))
  (let ((data (deref (field-pointer code 'data))))
    (let ((left-pointer (pointer+ data (wrap-cast isize left)))
          (right-pointer (pointer+ data (wrap-cast isize right))))
      (let ((left-byte (deref left-pointer)) (right-byte (deref right-pointer)))
        (store left-pointer right-byte)
        (store right-pointer left-byte)
        1))))

(defun native_startup_reverse_bytes (context code left right)
  (declare (type (ptr native_compile_context) context)
           (type (ptr byte_buffer) code) (type usize left right)
           (returns c-int))
  (store (field-pointer context 'fold_cursor) left)
  (store (field-pointer context 'inline_cursor) right)
  (while (< (deref (field-pointer context 'fold_cursor))
            (deref (field-pointer context 'inline_cursor)))
    (native_startup_swap_bytes code
      (deref (field-pointer context 'fold_cursor))
      (deref (field-pointer context 'inline_cursor)))
    (store (field-pointer context 'fold_cursor)
           (wrap+ (deref (field-pointer context 'fold_cursor)) 1))
    (store (field-pointer context 'inline_cursor)
           (wrap- (deref (field-pointer context 'inline_cursor)) 1))
    (wrap-cast c-int 1))
  1)

(defun native_startup_rotate_code (context code source-size startup-size total-size)
  (declare (type (ptr native_compile_context) context)
           (type (ptr byte_buffer) code)
           (type usize source-size startup-size total-size)
           (returns c-int))
  (if (= startup-size 0) 0
      (if (= (native_startup_reverse_bytes context code 0 (wrap- total-size 1)) 0) 0
          (if (= (native_startup_reverse_bytes context code 0 (wrap- startup-size 1)) 0) 0
              (if (= (native_startup_reverse_bytes context code startup-size
                                                    (wrap- total-size 1)) 0)
                  0 1)))))

(defun native_startup_swap_functions (left right)
  (declare (type (ptr native_function) left right) (returns c-int))
  (let ((name (deref (field-pointer left 'name)))
        (name-length (deref (field-pointer left 'name_length)))
        (offset (deref (field-pointer left 'offset)))
        (size (deref (field-pointer left 'size)))
        (arity (deref (field-pointer left 'arity)))
        (exported (deref (field-pointer left 'exported)))
        (imported (deref (field-pointer left 'imported)))
        (referenced (deref (field-pointer left 'referenced)))
        (frame-size (deref (field-pointer left 'frame_size)))
        (prologue-size (deref (field-pointer left 'prologue_size))))
    (store (field-pointer left 'name) (deref (field-pointer right 'name)))
    (store (field-pointer left 'name_length) (deref (field-pointer right 'name_length)))
    (store (field-pointer left 'offset) (deref (field-pointer right 'offset)))
    (store (field-pointer left 'size) (deref (field-pointer right 'size)))
    (store (field-pointer left 'arity) (deref (field-pointer right 'arity)))
    (store (field-pointer left 'exported) (deref (field-pointer right 'exported)))
    (store (field-pointer left 'imported) (deref (field-pointer right 'imported)))
    (store (field-pointer left 'referenced) (deref (field-pointer right 'referenced)))
    (store (field-pointer left 'frame_size) (deref (field-pointer right 'frame_size)))
    (store (field-pointer left 'prologue_size) (deref (field-pointer right 'prologue_size)))
    (store (field-pointer right 'name) name)
    (store (field-pointer right 'name_length) name-length)
    (store (field-pointer right 'offset) offset)
    (store (field-pointer right 'size) size)
    (store (field-pointer right 'arity) arity)
    (store (field-pointer right 'exported) exported)
    (store (field-pointer right 'imported) imported)
    (store (field-pointer right 'referenced) referenced)
    (store (field-pointer right 'frame_size) frame-size)
    (store (field-pointer right 'prologue_size) prologue-size)
    1))

(defun native_startup_rotate_functions (context functions count index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_function) functions) (type usize count index)
           (returns c-int))
  (store (field-pointer context 'fold_cursor) index)
  (while (< 0 (deref (field-pointer context 'fold_cursor)))
    (let ((left (native_function_at functions
                    (wrap- (deref (field-pointer context 'fold_cursor)) 1)))
          (right (native_function_at functions
                     (deref (field-pointer context 'fold_cursor)))))
      (native_startup_swap_functions left right)
      (store (field-pointer context 'fold_cursor)
             (wrap- (deref (field-pointer context 'fold_cursor)) 1))
      (wrap-cast c-int 1)))
  (wrap-cast c-int 1))

(defun native_startup_shift_source_offsets (context functions count startup-size index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_function) functions) (type usize count startup-size index)
           (returns c-int))
  (store (field-pointer context 'fold_cursor) index)
  (while (< (deref (field-pointer context 'fold_cursor)) count)
    (let ((function (native_function_at functions
                      (deref (field-pointer context 'fold_cursor)))))
      (store (field-pointer function 'offset)
             (wrap+ (deref (field-pointer function 'offset)) startup-size)))
    (store (field-pointer context 'fold_cursor)
           (wrap+ (deref (field-pointer context 'fold_cursor)) 1))
    (wrap-cast c-int 1))
  (wrap-cast c-int 1))

(defun native_startup_adjust_call_fixups (context arena source-count source-size
                                          startup-size index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_fixup_arena) arena)
           (type usize source-count source-size startup-size index)
           (returns c-int))
  (store (field-pointer context 'fold_cursor) index)
  (while (< (deref (field-pointer context 'fold_cursor))
            (deref (field-pointer arena 'count)))
    (let ((entry (call_fixup_at arena (deref (field-pointer context 'fold_cursor)))))
      (if (< (deref (field-pointer context 'fold_cursor)) source-count)
          (store (field-pointer entry 'instruction)
                 (wrap+ (deref (field-pointer entry 'instruction)) startup-size))
          (store (field-pointer entry 'instruction)
                 (wrap- (deref (field-pointer entry 'instruction)) source-size)))
      (store (field-pointer entry 'target)
             (wrap+ (deref (field-pointer entry 'target)) 1)))
    (store (field-pointer context 'fold_cursor)
           (wrap+ (deref (field-pointer context 'fold_cursor)) 1))
    (wrap-cast c-int 1))
  (wrap-cast c-int 1))

(defun native_startup_swap_call_fixups (left right)
  (declare (type (ptr native_call_fixup) left right) (returns c-int))
  (let ((instruction (deref (field-pointer left 'instruction)))
        (target (deref (field-pointer left 'target))))
    (store (field-pointer left 'instruction) (deref (field-pointer right 'instruction)))
    (store (field-pointer left 'target) (deref (field-pointer right 'target)))
    (store (field-pointer right 'instruction) instruction)
    (store (field-pointer right 'target) target)
    1))

(defun native_startup_bubble_call_fixup (context arena index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_fixup_arena) arena) (type usize index)
           (returns c-int))
  (store (field-pointer context 'fold_cursor) index)
  (while (< 0 (deref (field-pointer context 'fold_cursor)))
    (let ((current (call_fixup_at arena (deref (field-pointer context 'fold_cursor))))
          (previous (call_fixup_at arena
                       (wrap- (deref (field-pointer context 'fold_cursor)) 1))))
      (if (< (deref (field-pointer current 'instruction))
             (deref (field-pointer previous 'instruction)))
          (progn
            (native_startup_swap_call_fixups previous current)
            (store (field-pointer context 'fold_cursor)
                   (wrap- (deref (field-pointer context 'fold_cursor)) 1)))
          (store (field-pointer context 'fold_cursor) 0))))
    (wrap-cast c-int 1)
  1)

(defun native_startup_sort_call_fixups (context arena index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_fixup_arena) arena) (type usize index)
           (returns c-int))
  (store (field-pointer context 'inline_cursor) index)
  (while (< (deref (field-pointer context 'inline_cursor))
            (deref (field-pointer arena 'count)))
    (native_startup_bubble_call_fixup context arena
      (deref (field-pointer context 'inline_cursor)))
    (store (field-pointer context 'inline_cursor)
           (wrap+ (deref (field-pointer context 'inline_cursor)) 1))
    (wrap-cast c-int 1))
  (wrap-cast c-int 1))

(defun native_startup_shift_fixup_positions (context arena startup-size index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_fixup_arena) arena) (type usize startup-size index)
           (returns c-int))
  (store (field-pointer context 'fold_cursor) index)
  (while (< (deref (field-pointer context 'fold_cursor))
            (deref (field-pointer arena 'count)))
    (let ((entry (call_fixup_at arena (deref (field-pointer context 'fold_cursor)))))
      (store (field-pointer entry 'instruction)
             (wrap+ (deref (field-pointer entry 'instruction)) startup-size)))
    (store (field-pointer context 'fold_cursor)
           (wrap+ (deref (field-pointer context 'fold_cursor)) 1))
    (wrap-cast c-int 1))
  (wrap-cast c-int 1))

(defun native_startup_shift_address_fixups (context arena startup-size index)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_fixup_arena) arena) (type usize startup-size index)
           (returns c-int))
  (store (field-pointer context 'fold_cursor) index)
  (while (< (deref (field-pointer context 'fold_cursor))
            (deref (field-pointer arena 'count)))
    (let ((entry (call_fixup_at arena (deref (field-pointer context 'fold_cursor)))))
      (store (field-pointer entry 'instruction)
             (wrap+ (deref (field-pointer entry 'instruction)) startup-size))
      (store (field-pointer entry 'target)
             (wrap+ (deref (field-pointer entry 'target)) 1)))
    (store (field-pointer context 'fold_cursor)
           (wrap+ (deref (field-pointer context 'fold_cursor)) 1))
    (wrap-cast c-int 1))
  (wrap-cast c-int 1))

(defun native_startup_move_to_front (context count source-size source-fixup-count)
  (declare (type (ptr native_compile_context) context)
           (type usize count source-size source-fixup-count) (returns c-int))
  (let ((code (deref (field-pointer context 'code)))
        (functions (deref (field-pointer context 'functions)))
        (calls (deref (field-pointer context 'fixups)))
        (addresses (deref (field-pointer context 'function_addresses)))
        (data-fixups (deref (field-pointer context 'data_fixups))))
    (let ((total-size (deref (field-pointer code 'length)))
          (startup-size (wrap- (deref (field-pointer code 'length)) source-size)))
      (if (= (native_startup_rotate_code context code source-size startup-size total-size) 0) 0
          (if (= (native_startup_shift_source_offsets context functions count startup-size 0) 0) 0
              (if (= (native_startup_rotate_functions context functions count count) 0) 0
                  (progn
                    (store (field-pointer (native_function_at functions 0) 'offset) 0)
                    (if (= (native_startup_adjust_call_fixups context calls source-fixup-count
                            source-size startup-size 0) 0) 0
                    (if (= (native_startup_sort_call_fixups context calls 1) 0) 0
                        (if (= (native_startup_shift_address_fixups context addresses
                                startup-size 0) 0) 0
                            (native_startup_shift_fixup_positions context data-fixups
                                startup-size 0)))))))))))
