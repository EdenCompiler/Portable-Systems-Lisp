(include "elf64_multi.lisp")
(include "elf64_target_calls.lisp")

;; ELF symbol order is local definitions, then global definitions/imports.
;; Relocation targets use symbol indices, independently of source-order IDs.
(defun elf_function_rank (functions target index rank)
  (declare (type (ptr native_function) functions)
           (type usize target index rank) (returns usize))
  (if (= index target) rank
      (let ((function (native_function_at functions index)))
        (elf_function_rank functions target (wrap+ index 1)
          (wrap+ rank (if (= (native_function_emitted_p function) 1)
                         (native_function_global_p function) (wrap-cast usize 0)))))))

(defun elf_import_symbol_index (functions count target output_target)
  (declare (type (ptr native_function) functions)
           (type usize count target) (type u32 output_target) (returns usize))
  (wrap+ (wrap+ (wrap+ 3 (elf_mapping_symbol_count output_target)) (local_function_count_from functions 0 count))
         (elf_function_rank functions (wrap- target 1) 0 0)))

(defun elf_call_target_p (code code_size functions count fixup output_target)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_call_fixup) fixup)
           (type usize code_size count) (type u32 output_target) (returns c-int))
  (let ((target (deref (field-pointer fixup 'target)))
        (position (deref (field-pointer fixup 'instruction))))
    (if (= target 0) 0
        (if (< count target) 0
            (if (< code_size (elf_call_width output_target)) 0
                (if (< (wrap- code_size (elf_call_width output_target)) position) 0
                    (let ((function (native_function_at functions (wrap- target 1))))
                      (if (= (deref (field-pointer function 'imported)) 1)
                          (if (= (deref (field-pointer function 'referenced)) 1)
                              (elf_encoded_call_p code position output_target 1) 0)
                          (elf_encoded_call_p code position output_target 0)))))))))

(defun elf_call_order_p (fixups index output_target)
  (declare (type (ptr native_fixup_arena) fixups) (type usize index) (type u32 output_target) (returns c-int))
  (if (= index 0) 1
      (let ((previous (call_fixup_at fixups (wrap- index 1)))
            (current (call_fixup_at fixups index)))
        (if (< (deref (field-pointer current 'instruction))
               (wrap+ (deref (field-pointer previous 'instruction)) (elf_call_width output_target))) 0 1))))

(defun elf_calls_valid_from (code code_size functions count fixups index output_target)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups)
           (type usize code_size count index) (type u32 output_target) (returns c-int))
  (if (= index (deref (field-pointer fixups 'count))) 1
      (if (= (elf_call_target_p code code_size functions count (call_fixup_at fixups index) output_target) 0) 0
          (if (= (elf_call_order_p fixups index output_target) 0) 0
              (elf_calls_valid_from code code_size functions count fixups (wrap+ index 1) output_target)))))

(defun elf_calls_reference_target_p (fixups target index)
  (declare (type (ptr native_fixup_arena) fixups)
           (type usize target index) (returns usize))
  (if (= index (deref (field-pointer fixups 'count))) (wrap-cast usize 0)
      (if (= target (deref (field-pointer (call_fixup_at fixups index) 'target)))
          (wrap-cast usize 1)
          (elf_calls_reference_target_p fixups target (wrap+ index 1)))))

(defun elf_import_references_p (functions count fixups index)
  (declare (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups)
           (type usize count index) (returns c-int))
  (if (= index count) 1
      (let ((function (native_function_at functions index)))
        (if (= (deref (field-pointer function 'imported)) 1)
            (if (= (deref (field-pointer function 'referenced))
                   (elf_calls_reference_target_p fixups (wrap+ index 1) 0))
                (elf_import_references_p functions count fixups (wrap+ index 1)) 0)
            (elf_import_references_p functions count fixups (wrap+ index 1))))))

(defun elf_import_call_count (functions fixups index)
  (declare (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups)
           (type usize index) (returns usize))
  (if (= index (deref (field-pointer fixups 'count))) (wrap-cast usize 0)
      (let ((target (deref (field-pointer (call_fixup_at fixups index) 'target))))
        (wrap+ (deref (field-pointer (native_function_at functions (wrap- target 1)) 'imported))
               (elf_import_call_count functions fixups (wrap+ index 1))))))

(defun emit_elf_import_relocation (buffer functions count fixup output_target)
  (declare (type (ptr byte_buffer) buffer) (type (ptr native_function) functions)
           (type (ptr native_call_fixup) fixup) (type usize count) (type u32 output_target) (returns c-int))
  (let ((symbol (elf_import_symbol_index functions count (deref (field-pointer fixup 'target)) output_target)))
    (emit_integer buffer (wrap-cast u64 (wrap+ (deref (field-pointer fixup 'instruction))
                                             (elf_call_field_offset output_target))) 8)
    (emit_integer buffer (wrap+ (wrap* (wrap-cast u64 symbol) #x100000000)
                                (elf_call_relocation_type output_target)) 8)
    (emit_integer buffer (elf_call_addend output_target) 8)
    1))

(defun emit_elf_call_relocations (buffer functions count fixups index output_target)
  (declare (type (ptr byte_buffer) buffer) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups)
           (type usize count index) (type u32 output_target) (returns c-int))
  (if (= index (deref (field-pointer fixups 'count))) 1
      (let ((fixup (call_fixup_at fixups index)))
        (let ((function (native_function_at functions (wrap- (deref (field-pointer fixup 'target)) 1))))
          (if (= (deref (field-pointer function 'imported)) 1)
              (emit_elf_import_relocation buffer functions count fixup output_target) (wrap-cast c-int 1))
          (emit_elf_call_relocations buffer functions count fixups (wrap+ index 1) output_target)))))

(defun emit_elf_linked_functions (code code_size functions count fixups buffer output_target)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups) (type (ptr byte_buffer) buffer)
           (type usize code_size count) (type u32 output_target) (returns c-int))
  (let ((names (wrap+ (multi_name_bytes functions count) (wrap* (elf_mapping_symbol_count output_target) 3)))
        (relocation_bytes (wrap* 24 (elf_import_call_count functions fixups 0))))
    (let ((sections (wrap+ (multi_section_offset code_size
                             (wrap+ (multi_function_count_from functions 0 count) (elf_mapping_symbol_count output_target))
                             names) relocation_bytes)))
      (if (= (room_for buffer (wrap+ sections 512)) 0) 0
          (progn
            (emit_elf_header buffer sections (native_target_elf_machine output_target) 0)
            (emit_source_bytes buffer code code_size)
            (emit_zero_until buffer (align8 (deref (field-pointer buffer 'length))))
            (emit_elf_call_relocations buffer functions count fixups 0 output_target)
            (emit_elf_target_symbols buffer functions count output_target)
            (emit_elf_target_names buffer functions count output_target)
            (emit_section_names buffer)
            (emit_zero_until buffer (align8 (deref (field-pointer buffer 'length))))
            (emit_multi_section_headers_extra buffer code_size functions count names relocation_bytes
                                               (elf_mapping_symbol_count output_target)))))))

(defun elf_calls_output_shape_p (code_size functions count buffer)
  (declare (type (ptr native_function) functions) (type (ptr byte_buffer) buffer)
           (type usize code_size count) (returns c-int))
  (if (= count 0) 0
      (if (< 16777215 count) 0
          (if (< 1048576 code_size) 0
              (if (= (deref (field-pointer buffer 'length)) 0)
                  (if (= (valid_function_names_p functions count) 0) 0
                      (valid_function_spans_p functions count code_size)) 0)))))

(defun elf_calls_arena_p (fixups)
  (declare (type (ptr native_fixup_arena) fixups) (returns c-int))
  (if (= (deref (field-pointer fixups 'error)) 0)
      (if (< (deref (field-pointer fixups 'capacity)) (deref (field-pointer fixups 'count))) 0 1) 0))

(defun write_elf64_calls_target (output_target code code_size functions count fixups buffer)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups) (type (ptr byte_buffer) buffer)
           (type usize code_size count) (type u32 output_target) (returns c-int) (c-export :c))
  (if (= (native_target_valid_p output_target) 0) 0
      (if (= (elf_calls_output_shape_p code_size functions count buffer) 0) 0
          (if (= (elf_target_function_spans_p functions count 0 output_target) 0) 0
              (if (= (elf_calls_arena_p fixups) 0) 0
                  (if (= (elf_calls_valid_from code code_size functions count fixups 0 output_target) 0) 0
                      (if (= (elf_import_references_p functions count fixups 0) 0) 0
                          (emit_elf_linked_functions code code_size functions count fixups buffer output_target))))))))

(defun write_elf64_calls (code code_size functions count fixups buffer)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups) (type (ptr byte_buffer) buffer)
           (type usize code_size count) (returns c-int) (c-export :c))
  (write_elf64_calls_target 0 code code_size functions count fixups buffer))
