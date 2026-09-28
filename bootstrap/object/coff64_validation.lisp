(include "coff64_relocations.lisp")

(defun coff_frame_shape_p (frame prologue)
  (declare (type usize frame prologue) (returns c-int))
  (if (= frame 0) 0
      (if (< 2147483584 frame) 0
          (if (= (bits-and frame 15) 0)
              (if (= prologue (if (< frame 4096) (wrap-cast usize 11)
                                  (wrap-cast usize 67))) 1 0)
              0))))

(defun coff_prologue_bytes_p (data frame prologue)
  (declare (type (ptr u8) data) (type usize frame prologue) (returns c-int))
  (let ((allocation (pointer+ data (wrap-cast isize (wrap- prologue 10)))))
    (if (= (deref data) #x55)
        (if (= (bits-and (read_u32_le allocation) #xffffff) #xec8148)
            (if (= (read_u32_le (pointer+ allocation 3)) (wrap-cast u64 frame))
                (if (= (bits-and (read_u32_le (pointer+ allocation 7)) #xffffff) #xe58948)
                    1 0) 0) 0) 0)))

(defun coff_encoded_prologue_p (code function)
  (declare (type (ptr u8) code) (type (ptr native_function) function) (returns c-int))
  (let ((frame (deref (field-pointer function 'frame_size)))
        (prologue (deref (field-pointer function 'prologue_size))))
    (if (= (coff_frame_shape_p frame prologue) 0) 0
        (coff_prologue_bytes_p
          (pointer+ code (wrap-cast isize (deref (field-pointer function 'offset))))
          frame prologue))))

(defun coff_function_metadata_from (code functions index count)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type usize index count) (returns c-int))
  (if (= index count) 1
      (let ((entry (native_function_at functions index)))
        (if (= (deref (field-pointer entry 'imported)) 1)
            (if (= (deref (field-pointer entry 'frame_size)) 0)
                (if (= (deref (field-pointer entry 'prologue_size)) 0)
                    (coff_function_metadata_from code functions (wrap+ index 1) count) 0) 0)
            (if (< (deref (field-pointer entry 'size))
                   (wrap+ (deref (field-pointer entry 'prologue_size)) 37)) 0
                (if (= (coff_encoded_prologue_p code entry) 0) 0
                    (coff_function_metadata_from code functions (wrap+ index 1) count)))))))

(defun coff_call_target_p (code code_size functions count fixup)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_call_fixup) fixup) (type usize code_size count) (returns c-int))
  (let ((target (deref (field-pointer fixup 'target)))
        (position (deref (field-pointer fixup 'instruction))))
    (if (= target 0) 0
        (if (< count target) 0
            (if (< code_size 5) 0
                (if (< (wrap- code_size 5) position) 0
                    (let ((entry (native_function_at functions (wrap- target 1)))
                          (data (pointer+ code (wrap-cast isize position))))
                      (if (= (deref data) #xe8)
                          (if (= (deref (field-pointer entry 'imported)) 1)
                              (if (= (deref (field-pointer entry 'referenced)) 1)
                                  (if (= (read_u32_le (pointer+ data 1)) 0) 1 0) 0)
                              1)
                          0))))))))

(defun coff_call_order_p (fixups index)
  (declare (type (ptr native_fixup_arena) fixups) (type usize index) (returns c-int))
  (if (= index 0) 1
      (if (< (deref (field-pointer (call_fixup_at fixups index) 'instruction))
             (wrap+ (deref (field-pointer (call_fixup_at fixups (wrap- index 1)) 'instruction)) 5))
          0 1)))

(defun coff_calls_valid_range (code code_size functions count fixups first last)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups)
           (type usize code_size count first last) (returns c-int))
  (if (= first last) 1
      (if (= (wrap+ first 1) last)
          (if (= (coff_call_order_p fixups first) 0) 0
              (coff_call_target_p code code_size functions count (call_fixup_at fixups first)))
          (let ((middle (wrap+ first (wrap-cast usize
                                 (shr64 (wrap-cast u64 (wrap- last first)) 1)))))
            (if (= (coff_calls_valid_range code code_size functions count fixups first middle) 0) 0
                (coff_calls_valid_range code code_size functions count fixups middle last))))))

(defun coff_import_call_count_range (functions fixups first last)
  (declare (type (ptr native_function) functions) (type (ptr native_fixup_arena) fixups)
           (type usize first last) (returns usize))
  (if (= first last) 0
      (if (= (wrap+ first 1) last)
          (deref (field-pointer
                   (native_function_at functions
                     (wrap- (deref (field-pointer (call_fixup_at fixups first) 'target)) 1))
                   'imported))
          (let ((middle (wrap+ first (wrap-cast usize
                                 (shr64 (wrap-cast u64 (wrap- last first)) 1)))))
            (wrap+ (coff_import_call_count_range functions fixups first middle)
                   (coff_import_call_count_range functions fixups middle last))))))

(defun coff_target_referenced_range (fixups target first last)
  (declare (type (ptr native_fixup_arena) fixups)
           (type usize target first last) (returns usize))
  (if (= first last) 0
      (if (= (wrap+ first 1) last)
          (if (= target (deref (field-pointer (call_fixup_at fixups first) 'target))) 1 0)
          (let ((middle (wrap+ first (wrap-cast usize
                                 (shr64 (wrap-cast u64 (wrap- last first)) 1)))))
            (if (= (coff_target_referenced_range fixups target first middle) 1) 1
                (coff_target_referenced_range fixups target middle last))))))

(defun coff_import_references_from (functions count fixups index)
  (declare (type (ptr native_function) functions) (type (ptr native_fixup_arena) fixups)
           (type usize count index) (returns c-int))
  (if (= index count) 1
      (let ((entry (native_function_at functions index)))
        (if (= (deref (field-pointer entry 'imported)) 1)
            (if (= (deref (field-pointer entry 'referenced))
                   (coff_target_referenced_range fixups (wrap+ index 1) 0
                                                 (deref (field-pointer fixups 'count))))
                (coff_import_references_from functions count fixups (wrap+ index 1)) 0)
            (coff_import_references_from functions count fixups (wrap+ index 1))))))

(defun coff_fixup_arena_p (fixups)
  (declare (type (ptr native_fixup_arena) fixups) (returns c-int))
  (if (= (deref (field-pointer fixups 'error)) 0)
      (if (< (deref (field-pointer fixups 'capacity)) (deref (field-pointer fixups 'count))) 0 1) 0))
