(include "riscv64_encode.lisp")
(include "fixups.lisp")

;; Fixed AUIPC/JALR pairs avoid the short JAL range. No RELAX relocations are
;; emitted: linker deletion must not invalidate already patched local calls.
(defun rv_pair_delta_p (position destination)
  (declare (type usize position destination) (returns c-int))
  (if (= (bits-and position 3) 0)
      (if (= (bits-and destination 3) 0)
          (if (< destination position)
              (if (< 2147483648 (wrap- position destination)) 0 1)
              (if (< 2147481599 (wrap- destination position)) 0 1)) 0) 0))

(defun rv_patch_pair (code position destination register result)
  (declare (type (ptr byte_buffer) code) (type usize position destination)
           (type u64 register result) (returns c-int))
  (if (= (rv_pair_delta_p position destination) 0) 0
      (let ((delta (wrap-cast u64 (wrap- destination position))))
        (if (= (patch_i32 code position
                 (wrap-cast s32 (wrap+ #x17 (wrap+ (wrap* register 128)
                   (bits-and (wrap+ delta 2048) #xfffff000))))) 0) 0
            (patch_i32 code (wrap+ position 4)
              (wrap-cast s32 (rv_i_word #x67 result register 0 delta)))))))

(defun rv_reserve_pair (code register result)
  (declare (type (ptr byte_buffer) code) (type u64 register result) (returns c-int))
  (if (= (rv_word code (wrap+ #x17 (wrap* register 128))) 0) 0
      (rv_i code #x67 result register 0 0)))

(defun rv_deferred_call (code fixups target)
  (declare (type (ptr byte_buffer) code) (type (ptr native_fixup_arena) fixups)
           (type usize target) (returns c-int))
  (if (= (record_call_fixup fixups (deref (field-pointer code 'length)) target) 0) 0
      (rv_reserve_pair code 1 1)))

(defun rv_call_placeholder_p (code position)
  (declare (type (ptr byte_buffer) code) (type usize position) (returns c-int))
  (let ((data (pointer+ (deref (field-pointer code 'data)) (wrap-cast isize position))))
    (if (= (read_u32_le data) #x97)
        (if (= (read_u32_le (pointer+ data 4)) #x80e7) 1 0) 0)))

(defun rv_patch_call_at (code functions count fixups index)
  (declare (type (ptr byte_buffer) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups) (type usize count index) (returns c-int))
  (let ((entry (call_fixup_at fixups index)))
    (let ((target (deref (field-pointer entry 'target)))
          (position (deref (field-pointer entry 'instruction)))
          (length (deref (field-pointer code 'length))))
      (if (= target 0) 0
          (if (< count target) 0
              (if (< length 8) 0
                  (if (< (wrap- length 8) position) 0
                      (if (= (bits-and position 3) 0)
                          (if (= (rv_call_placeholder_p code position) 0) 0
                              (let ((function (native_function_at functions (wrap- target 1))))
                                (if (= (deref (field-pointer function 'imported)) 1) 1
                                    (let ((destination (deref (field-pointer function 'offset))))
                                      (if (< (wrap- length 4) destination) 0
                                          (rv_patch_pair code position destination 1 1)))))) 0))))))))

(defun rv_patch_calls_from (code functions count fixups index)
  (declare (type (ptr byte_buffer) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups) (type usize count index) (returns c-int))
  (if (= index (deref (field-pointer fixups 'count))) 1
      (if (= (rv_patch_call_at code functions count fixups index) 0) 0
          (rv_patch_calls_from code functions count fixups (wrap+ index 1)))))

(defun rv_patch_calls (code functions count fixups)
  (declare (type (ptr byte_buffer) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups) (type usize count) (returns c-int))
  (if (= (deref (field-pointer fixups 'error)) 0)
      (if (< (deref (field-pointer fixups 'capacity)) (deref (field-pointer fixups 'count))) 0
          (rv_patch_calls_from code functions count fixups 0)) 0))
