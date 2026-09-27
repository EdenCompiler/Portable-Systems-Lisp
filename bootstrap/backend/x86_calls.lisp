(include "x86_calls_types.lisp")
(include "fixups.lisp")
(include "common.lisp")
(include "../binary.lisp")

;; Calls are encoded with an empty rel32 field, then patched after all function
;; offsets are known. Defined calls are patched within .text; imported calls
;; retain zero placeholders for the ELF writer's PLT32 relocations.
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

(defun patch_defined_call (code function instruction)
  (declare (type (ptr byte_buffer) code)
           (type (ptr native_function) function)
           (type usize instruction) (returns c-int))
  (let ((destination (deref (field-pointer function 'offset))))
    (if (< (deref (field-pointer code 'length)) destination) 0
        (patch_i32 code (wrap+ instruction 1)
                   (wrap-cast s32 (wrap- destination (wrap+ instruction 5)))))))

(defun patch_call_at (code functions count fixups index)
  (declare (type (ptr byte_buffer) code)
           (type (ptr native_function) functions)
           (type usize count index)
           (type (ptr native_fixup_arena) fixups) (returns c-int))
  (let ((entry (call_fixup_at fixups index)))
    (let ((target (deref (field-pointer entry 'target)))
          (instruction (deref (field-pointer entry 'instruction))))
      (if (= target 0) 0
          (if (< count target) 0
              (if (< (deref (field-pointer code 'length)) 5) 0
                  (if (< (wrap- (deref (field-pointer code 'length)) 5) instruction) 0
                      (let ((function (native_function_at functions (wrap- target 1))))
                        (if (= (deref (field-pointer function 'imported)) 1) 1
                            (patch_defined_call code function instruction))))))))))

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
