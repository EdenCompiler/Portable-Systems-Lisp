(include "common.lisp")
(include "../binary.lisp")

;; Calls are encoded with an empty rel32 field, then patched after all function
;; offsets are known. The emitted ELF object needs no relocation for calls
;; within its own .text section.
(defcstruct native_call_fixup
  (instruction usize)
  (target usize))

(defcstruct native_fixup_arena
  (items (ptr native_call_fixup))
  (count usize)
  (capacity usize)
  (error u32))

(defun call_fixup_at (arena index)
  (declare (type (ptr native_fixup_arena) arena)
           (type usize index)
           (returns (ptr native_call_fixup)))
  (pointer+ (deref (field-pointer arena 'items))
            (wrap-cast isize index)))

(defun record_call_fixup (arena instruction target)
  (declare (type (ptr native_fixup_arena) arena)
           (type usize instruction target)
           (returns c-int))
  (let ((count (deref (field-pointer arena 'count))))
    (if (< count (deref (field-pointer arena 'capacity)))
        (let ((entry (call_fixup_at arena count)))
          (store (field-pointer entry 'instruction) instruction)
          (store (field-pointer entry 'target) target)
          (store (field-pointer arena 'count) (wrap+ count 1))
          1)
        (progn
          (store (field-pointer arena 'error) 1)
          0))))

(defun call_padding_p (stack_depth)
  (declare (type usize stack_depth) (returns c-int))
  (if (= (bits-and (wrap-cast u64 stack_depth) 1) 1) 1 0))

(defun emit_deferred_call (code fixups target stack_depth)
  (declare (type (ptr byte_buffer) code)
           (type (ptr native_fixup_arena) fixups)
           (type usize target stack_depth)
           (returns c-int))
  (if (= (room_for code (if (= (call_padding_p stack_depth) 1)
                            13 5)) 0)
      0
      (if (= (deref (field-pointer fixups 'count))
             (deref (field-pointer fixups 'capacity)))
          0
          (progn
            (if (= (call_padding_p stack_depth) 1)
                (emit_integer code #x08ec8348 4) ; sub rsp, 8
                (wrap-cast c-int 1))
            (let ((start (deref (field-pointer code 'length))))
              (emit_byte_unchecked code #xe8)
              (emit_integer code 0 4)
              (record_call_fixup fixups start target)
              (if (= (call_padding_p stack_depth) 1)
                  (emit_integer code #x08c48348 4) ; add rsp, 8
                  (wrap-cast c-int 1)))))))

(defun patch_call_at (code functions count fixups index)
  (declare (type (ptr byte_buffer) code)
           (type (ptr native_function) functions)
           (type usize count index)
           (type (ptr native_fixup_arena) fixups)
           (returns c-int))
  (let ((entry (call_fixup_at fixups index)))
    (let ((target (deref (field-pointer entry 'target)))
          (instruction (deref (field-pointer entry 'instruction))))
      (if (= target 0)
          0
          (if (< count target)
              0
              (if (< (deref (field-pointer code 'length))
                     (wrap+ instruction 5))
                  0
                  (let ((destination
                         (deref (field-pointer
                                 (native_function_at functions
                                                     (wrap- target 1))
                                 'offset))))
                    (if (< (deref (field-pointer code 'length)) destination)
                        0
                        (patch_i32
                         code (wrap+ instruction 1)
                         (wrap-cast s32
                                    (wrap- destination
                                           (wrap+ instruction 5))))))))))))

(defun patch_call_fixups_from (code functions count fixups index)
  (declare (type (ptr byte_buffer) code)
           (type (ptr native_function) functions)
           (type usize count index)
           (type (ptr native_fixup_arena) fixups)
           (returns c-int))
  (if (= index (deref (field-pointer fixups 'count)))
      1
      (if (= (patch_call_at code functions count fixups index) 0)
          0
          (patch_call_fixups_from code functions count fixups
                                  (wrap+ index 1)))))

(defun patch_call_fixups (code functions count fixups)
  (declare (type (ptr byte_buffer) code)
           (type (ptr native_function) functions)
           (type usize count)
           (type (ptr native_fixup_arena) fixups)
           (returns c-int)
           (c-export :c))
  (if (= (deref (field-pointer fixups 'error)) 0)
      (patch_call_fixups_from code functions count fixups 0)
      0))
