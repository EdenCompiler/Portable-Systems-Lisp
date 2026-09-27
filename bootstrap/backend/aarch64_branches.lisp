(include "aarch64_encode.lisp")
(include "fixups.lisp")

(defun a64_branch_delta_p (position destination bits)
  (declare (type usize position destination) (type u32 bits) (returns c-int))
  (if (= (bits-and position 3) 0)
      (if (= (bits-and destination 3) 0)
          (let ((limit (if (= bits 26) (wrap-cast usize 134217728) (wrap-cast usize 1048576))))
            (if (< destination position)
                (if (< limit (wrap- position destination)) 0 1)
                (if (< (wrap- destination position) limit) 1 0))) 0) 0))

(defun a64_patch_branch (code position destination base bits)
  (declare (type (ptr byte_buffer) code) (type usize position destination)
           (type u64 base) (type u32 bits) (returns c-int))
  (if (= (a64_branch_delta_p position destination bits) 0) 0
      (let ((mask (if (= bits 26) (wrap-cast u64 #x3ffffff) (wrap-cast u64 #x7ffff))))
        (let ((delta (bits-and (shr64 (wrap-cast u64 (wrap- destination position)) 2) mask)))
          (patch_i32 code position (wrap-cast s32 (wrap+ base
                                     (if (= bits 26) delta (wrap* delta 32)))))))))

(defun a64_deferred_call (code fixups target)
  (declare (type (ptr byte_buffer) code) (type (ptr native_fixup_arena) fixups)
           (type usize target) (returns c-int))
  (let ((position (deref (field-pointer code 'length))))
    (if (= (record_call_fixup fixups position target) 0) 0 (a64_word code #x94000000))))

(defun a64_patch_call_at (code functions count fixups index)
  (declare (type (ptr byte_buffer) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups) (type usize count index) (returns c-int))
  (let ((entry (call_fixup_at fixups index)))
    (let ((target (deref (field-pointer entry 'target)))
          (position (deref (field-pointer entry 'instruction)))
          (length (deref (field-pointer code 'length))))
      (if (= target 0) 0
          (if (< count target) 0
              (if (< length 4) 0
                  (if (< (wrap- length 4) position) 0
                      (if (= (bits-and position 3) 0)
                          (if (= (read_u32_le (pointer+ (deref (field-pointer code 'data))
                                                    (wrap-cast isize position))) #x94000000)
                              (let ((function (native_function_at functions (wrap- target 1))))
                                (if (= (deref (field-pointer function 'imported)) 1) 1
                                    (let ((destination (deref (field-pointer function 'offset))))
                                      (if (< (wrap- length 4) destination) 0
                                          (a64_patch_branch code position destination #x94000000 26))))) 0) 0))))))))

(defun a64_patch_calls_from (code functions count fixups index)
  (declare (type (ptr byte_buffer) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups) (type usize count index) (returns c-int))
  (if (= index (deref (field-pointer fixups 'count))) 1
      (if (= (a64_patch_call_at code functions count fixups index) 0) 0
          (a64_patch_calls_from code functions count fixups (wrap+ index 1)))))

(defun a64_patch_calls (code functions count fixups)
  (declare (type (ptr byte_buffer) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups) (type usize count) (returns c-int))
  (if (= (deref (field-pointer fixups 'error)) 0)
      (if (< (deref (field-pointer fixups 'capacity)) (deref (field-pointer fixups 'count))) 0
          (a64_patch_calls_from code functions count fixups 0)) 0))
