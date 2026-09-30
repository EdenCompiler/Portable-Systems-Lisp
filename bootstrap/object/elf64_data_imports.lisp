(include "elf64_calls.lisp")

(defun data_import_alignment_p (alignment)
  (declare (type usize alignment) (returns c-int))
  (if (= alignment 0) 0
      (if (< 4096 alignment) 0
          (if (= (bits-and alignment (wrap- alignment 1)) 0) 1 0))))

(defun native_data_import_name_valid_p (entry)
  (declare (type (ptr native_data_import) entry) (returns c-int))
  (let ((length (deref (field-pointer entry 'name_length))))
    (if (= length 0) 0
        (if (< 255 length) 0
            (if (= (name_ascii_p (deref (field-pointer entry 'name)) 0 length) 0) 0
                (if (< 1 (deref (field-pointer entry 'defined))) 0
                    (if (< 1 (deref (field-pointer entry 'referenced))) 0
                        (if (= (deref (field-pointer entry 'size)) 0) 0
                            (if (= (deref (field-pointer entry 'defined)) 1)
                                (if (< 8 (deref (field-pointer entry 'size))) 0
                                    (data_import_alignment_p
                                     (deref (field-pointer entry 'alignment))))
                                (data_import_alignment_p
                                 (deref (field-pointer entry 'alignment))))))))))))

(defun native_data_emitted_p (entry)
  (declare (type (ptr native_data_import) entry) (returns usize))
  (if (= (deref (field-pointer entry 'defined)) 1) (wrap-cast usize 1)
      (wrap-cast usize (deref (field-pointer entry 'referenced)))))

(defun same_data_import_name_p (left right)
  (declare (type (ptr native_data_import) left right) (returns c-int))
  (let ((length (deref (field-pointer left 'name_length))))
    (if (= length (deref (field-pointer right 'name_length)))
        (same_name_bytes_p (deref (field-pointer left 'name))
                           (deref (field-pointer right 'name)) length)
        0)))

(defun earlier_data_import_name_p (imports candidate index)
  (declare (type (ptr native_data_import) imports candidate)
           (type usize index) (returns c-int))
  (if (= index 0) 0
      (if (= (same_data_import_name_p
              (pointer+ imports (wrap-cast isize (wrap- index 1))) candidate) 1) 1
          (earlier_data_import_name_p imports candidate (wrap- index 1)))))

(defun valid_data_imports_from (imports index count)
  (declare (type (ptr native_data_import) imports)
           (type usize index count) (returns c-int))
  (if (= index count) 1
      (let ((entry (pointer+ imports (wrap-cast isize index))))
        (if (= (native_data_import_name_valid_p entry) 0) 0
            (if (= (earlier_data_import_name_p imports entry index) 1) 0
                (valid_data_imports_from imports (wrap+ index 1) count))))))

(defun data_import_emitted_count_from (imports index count)
  (declare (type (ptr native_data_import) imports)
           (type usize index count) (returns usize))
  (if (= index count) 0
      (wrap+ (native_data_emitted_p
              (pointer+ imports (wrap-cast isize index)))
             (data_import_emitted_count_from imports (wrap+ index 1) count))))

(defun data_import_name_bytes_from (imports index count)
  (declare (type (ptr native_data_import) imports)
           (type usize index count) (returns usize))
  (if (= index count) 0
      (let ((entry (pointer+ imports (wrap-cast isize index))))
        (wrap+ (if (= (native_data_emitted_p entry) 1)
                   (wrap+ (deref (field-pointer entry 'name_length)) 1)
                   (wrap-cast usize 0))
               (data_import_name_bytes_from imports (wrap+ index 1) count)))))

(defun data_import_rank_from (imports target index rank)
  (declare (type (ptr native_data_import) imports)
           (type usize target index rank) (returns usize))
  (if (= index target) rank
      (data_import_rank_from
       imports target (wrap+ index 1)
       (wrap+ rank
              (native_data_emitted_p
               (pointer+ imports (wrap-cast isize index)))))))

(defun compiled_data_align_up (value alignment)
  (declare (type usize value alignment) (returns usize))
  (bits-and (wrap+ value (wrap- alignment 1)) (wrap- 0 alignment)))

(defun defined_data_size_from (imports index count offset)
  (declare (type (ptr native_data_import) imports)
           (type usize index count offset) (returns usize))
  (if (= index count) offset
      (let ((entry (pointer+ imports (wrap-cast isize index))))
        (if (= (deref (field-pointer entry 'defined)) 0)
            (defined_data_size_from imports (wrap+ index 1) count offset)
            (defined_data_size_from
             imports (wrap+ index 1) count
             (wrap+ (compiled_data_align_up
                     offset (deref (field-pointer entry 'alignment)))
                    (deref (field-pointer entry 'size))))))))

(defun defined_data_size (imports count)
  (declare (type (ptr native_data_import) imports)
           (type usize count) (returns usize))
  (defined_data_size_from imports 0 count 0))

(defun defined_data_max_alignment_from (imports index count maximum)
  (declare (type (ptr native_data_import) imports)
           (type usize index count maximum) (returns usize))
  (if (= index count) maximum
      (let ((entry (pointer+ imports (wrap-cast isize index))))
        (defined_data_max_alignment_from
         imports (wrap+ index 1) count
         (if (= (deref (field-pointer entry 'defined)) 0) maximum
             (let ((alignment (deref (field-pointer entry 'alignment))))
               (if (< maximum alignment) alignment maximum)))))))

(defun defined_data_max_alignment (imports count)
  (declare (type (ptr native_data_import) imports)
           (type usize count) (returns usize))
  (defined_data_max_alignment_from imports 0 count 1))

(defun defined_data_offset_from (imports index stop offset)
  (declare (type (ptr native_data_import) imports)
           (type usize index stop offset) (returns usize))
  (if (= index stop) offset
      (let ((entry (pointer+ imports (wrap-cast isize index))))
        (defined_data_offset_from
         imports (wrap+ index 1) stop
         (if (= (deref (field-pointer entry 'defined)) 0) offset
             (wrap+ (compiled_data_align_up
                     offset (deref (field-pointer entry 'alignment)))
                    (deref (field-pointer entry 'size))))))))

(defun defined_data_offset (imports index)
  (declare (type (ptr native_data_import) imports)
           (type usize index) (returns usize))
  (let ((entry (pointer+ imports (wrap-cast isize index))))
    (compiled_data_align_up
     (defined_data_offset_from imports 0 index 0)
     (deref (field-pointer entry 'alignment)))))

(defun emit_defined_data_from (buffer imports index count data_start)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_import) imports)
           (type usize index count data_start) (returns c-int))
  (if (= index count) 1
      (let ((entry (pointer+ imports (wrap-cast isize index))))
        (if (= (deref (field-pointer entry 'defined)) 1)
            (progn
              (emit_zero_until
               buffer (wrap+ data_start (defined_data_offset imports index)))
              (emit_integer buffer (deref (field-pointer entry 'initial))
                            (deref (field-pointer entry 'size)))
              (emit_defined_data_from buffer imports (wrap+ index 1)
                                      count data_start))
            (emit_defined_data_from buffer imports (wrap+ index 1)
                                    count data_start)))))

(defun elf_data_label_count (fixups output_target)
  (declare (type (ptr native_fixup_arena) fixups)
           (type u32 output_target) (returns usize))
  (if (= output_target 2) (deref (field-pointer fixups 'count))
      (wrap-cast usize 0)))

(defun elf_data_import_symbol_index (functions function_count imports target
                                     output_target data_labels)
  (declare (type (ptr native_function) functions)
           (type (ptr native_data_import) imports)
           (type usize function_count target data_labels) (type u32 output_target)
           (returns usize))
  (wrap+ (wrap+ (wrap+ (wrap+ 3 (elf_mapping_symbol_count output_target))
                       data_labels)
                (multi_function_count_from functions 0 function_count))
         (data_import_rank_from imports (wrap- target 1) 0 0)))

(defun elf_data_fixup_valid_p (code code_size imports import_count fixup output_target)
  (declare (type (ptr u8) code) (type (ptr native_data_import) imports)
           (type (ptr native_call_fixup) fixup)
           (type usize code_size import_count) (type u32 output_target)
           (returns c-int))
  (let ((target (deref (field-pointer fixup 'target)))
        (position (deref (field-pointer fixup 'instruction)))
        (width (if (= output_target 0) (wrap-cast usize 7)
                   (wrap-cast usize 8))))
    (if (= target 0) 0
        (if (< import_count target) 0
            (if (< code_size width) 0
                (if (< (wrap- code_size width) position) 0
                    (let ((bytes (pointer+ code (wrap-cast isize position)))
                          (entry (pointer+ imports
                                           (wrap-cast isize (wrap- target 1)))))
                      (if (= (deref (field-pointer entry 'referenced)) 0) 0
                          (if (= output_target 0)
                              (if (= (deref bytes) #x48)
                                  (if (= (deref (pointer+ bytes 1)) #x8b)
                                      (if (= (deref (pointer+ bytes 2)) #x05)
                                          (if (= (read_u32_le (pointer+ bytes 3)) 0) 1 0)
                                          0)
                                      0)
                                  0)
                              (if (= (bits-and position 3) 0)
                                  (if (= output_target 1)
                                      (if (= (read_u32_le bytes) #x90000009)
                                          (if (= (read_u32_le (pointer+ bytes 4))
                                                 #xf9400129) 1 0)
                                          0)
                                      (if (= (read_u32_le bytes) #x00000297)
                                          (if (= (read_u32_le (pointer+ bytes 4))
                                                 #x0002b283) 1 0)
                                          0))
                                  0))))))))))

(defun data_fixup_order_p (fixups index width)
  (declare (type (ptr native_fixup_arena) fixups)
           (type usize index width) (returns c-int))
  (if (= index 0) 1
      (if (< (deref (field-pointer (call_fixup_at fixups index) 'instruction))
             (wrap+ (deref (field-pointer
                            (call_fixup_at fixups (wrap- index 1)) 'instruction)) width))
          0 1)))

(defun data_fixups_valid_from (code code_size imports import_count fixups index output_target)
  (declare (type (ptr u8) code) (type (ptr native_data_import) imports)
           (type (ptr native_fixup_arena) fixups)
           (type usize code_size import_count index) (type u32 output_target)
           (returns c-int))
  (if (= index (deref (field-pointer fixups 'count))) 1
      (if (= (data_fixup_order_p fixups index
                                 (if (= output_target 0) (wrap-cast usize 7)
                                     (wrap-cast usize 8))) 0) 0
          (if (= (elf_data_fixup_valid_p code code_size imports import_count
                                         (call_fixup_at fixups index)
                                         output_target) 0) 0
              (data_fixups_valid_from code code_size imports import_count
                                      fixups (wrap+ index 1) output_target)))))

(defun data_import_referenced_by_fixup_p (fixups target index)
  (declare (type (ptr native_fixup_arena) fixups)
           (type usize target index) (returns usize))
  (if (= index (deref (field-pointer fixups 'count))) (wrap-cast usize 0)
      (if (= target (deref (field-pointer (call_fixup_at fixups index) 'target)))
          (wrap-cast usize 1)
          (data_import_referenced_by_fixup_p fixups target (wrap+ index 1)))))

(defun data_import_references_valid_from (imports count fixups index)
  (declare (type (ptr native_data_import) imports)
           (type (ptr native_fixup_arena) fixups)
           (type usize count index) (returns c-int))
  (if (= index count) 1
      (if (= (wrap-cast usize
                        (deref (field-pointer
                                (pointer+ imports (wrap-cast isize index))
                                'referenced)))
             (data_import_referenced_by_fixup_p fixups (wrap+ index 1) 0))
          (data_import_references_valid_from imports count fixups (wrap+ index 1)) 0)))

(defun emit_elf_data_import_relocation_record (buffer offset symbol kind addend)
  (declare (type (ptr byte_buffer) buffer)
           (type usize offset symbol) (type u64 kind addend) (returns c-int))
  (emit_integer buffer (wrap-cast u64 offset) 8)
  (emit_integer buffer
                (wrap+ (wrap* (wrap-cast u64 symbol) #x100000000) kind) 8)
  (emit_integer buffer addend 8))

(defun emit_elf_data_import_relocations (buffer functions function_count imports
                                         fixups index output_target)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_function) functions)
           (type (ptr native_data_import) imports)
           (type (ptr native_fixup_arena) fixups)
           (type usize function_count index) (type u32 output_target)
           (returns c-int))
  (if (= index (deref (field-pointer fixups 'count))) 1
      (let ((fixup (call_fixup_at fixups index)))
        (let ((position (deref (field-pointer fixup 'instruction)))
              (symbol (elf_data_import_symbol_index
                       functions function_count imports
                       (deref (field-pointer fixup 'target)) output_target
                       (elf_data_label_count fixups output_target))))
          (if (= output_target 0)
              (emit_elf_data_import_relocation_record
               buffer (wrap+ position 3) symbol 9 (wrap- (wrap-cast u64 0) 4))
              (if (= output_target 1)
                  (progn
                    (emit_elf_data_import_relocation_record buffer position symbol 311 0)
                    (emit_elf_data_import_relocation_record
                     buffer (wrap+ position 4) symbol 312 0))
                  (progn
                    (emit_elf_data_import_relocation_record buffer position symbol 20 0)
                    (emit_elf_data_import_relocation_record
                     buffer (wrap+ position 4)
                     (wrap+ (wrap+ 3 (elf_mapping_symbol_count output_target)) index)
                     24 0)))))
        (emit_elf_data_import_relocations buffer functions function_count
                                          imports fixups (wrap+ index 1)
                                          output_target))))

(defun emit_elf_data_label_symbols (buffer fixups index)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_fixup_arena) fixups)
           (type usize index) (returns c-int))
  (if (= index (deref (field-pointer fixups 'count))) 1
      (progn
        (emit_symbol buffer 0 0 1
                     (wrap-cast u64
                                (deref (field-pointer (call_fixup_at fixups index)
                                                      'instruction)))
                     0)
        (emit_elf_data_label_symbols buffer fixups (wrap+ index 1)))))

(defun emit_elf_calls_data_symbols (buffer functions function_count fixups output_target)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups)
           (type usize function_count) (type u32 output_target)
           (returns c-int))
  (emit_symbol buffer 0 0 0 0 0)
  (emit_symbol buffer 0 3 1 0 0)
  (emit_symbol buffer 0 3 2 0 0)
  (if (= (elf_mapping_symbol_count output_target) 1)
      (emit_symbol buffer 1 0 1 0 0) (wrap-cast c-int 1))
  (if (= output_target 2)
      (emit_elf_data_label_symbols buffer fixups 0) (wrap-cast c-int 1))
  (let ((next (emit_selected_symbols_from
               buffer functions 0 function_count
               (wrap+ 1 (wrap* (elf_mapping_symbol_count output_target) 3)) 0)))
    (emit_selected_symbols_from buffer functions 0 function_count next 1))
  1)

(defun emit_elf_import_relocation_with_data_labels
    (buffer functions function_count fixup output_target data_labels)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_function) functions)
           (type (ptr native_call_fixup) fixup)
           (type usize function_count data_labels) (type u32 output_target)
           (returns c-int))
  (let ((symbol (wrap+ (elf_import_symbol_index
                        functions function_count
                        (deref (field-pointer fixup 'target)) output_target)
                       data_labels)))
    (emit_integer buffer
                  (wrap-cast u64
                             (wrap+ (deref (field-pointer fixup 'instruction))
                                    (elf_call_field_offset output_target))) 8)
    (emit_integer buffer
                  (wrap+ (wrap* (wrap-cast u64 symbol) #x100000000)
                         (elf_call_relocation_type output_target)) 8)
    (emit_integer buffer (elf_call_addend output_target) 8)
    1))

(defun emit_elf_call_relocations_with_data_labels
    (buffer functions function_count fixups index output_target data_labels)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups)
           (type usize function_count index data_labels)
           (type u32 output_target) (returns c-int))
  (if (= index (deref (field-pointer fixups 'count))) 1
      (let ((fixup (call_fixup_at fixups index)))
        (let ((function
               (native_function_at
                functions (wrap- (deref (field-pointer fixup 'target)) 1))))
          (if (= (deref (field-pointer function 'imported)) 1)
              (emit_elf_import_relocation_with_data_labels
               buffer functions function_count fixup output_target data_labels)
              (wrap-cast c-int 1))
          (emit_elf_call_relocations_with_data_labels
           buffer functions function_count fixups (wrap+ index 1)
           output_target data_labels)))))

(defun emit_elf_data_import_symbols (buffer imports index count name_offset)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_import) imports)
           (type usize index count name_offset) (returns usize))
  (if (= index count) name_offset
      (let ((entry (pointer+ imports (wrap-cast isize index))))
        (if (= (native_data_emitted_p entry) 1)
            (progn
              (emit_symbol
               buffer (wrap-cast u64 name_offset) 17
               (if (= (deref (field-pointer entry 'defined)) 1) 2 0)
               (if (= (deref (field-pointer entry 'defined)) 1)
                   (wrap-cast u64 (defined_data_offset imports index)) 0)
               (if (= (deref (field-pointer entry 'defined)) 1)
                   (wrap-cast u64 (deref (field-pointer entry 'size))) 0))
              (emit_elf_data_import_symbols
               buffer imports (wrap+ index 1) count
               (wrap+ name_offset
                      (wrap+ (deref (field-pointer entry 'name_length)) 1))))
            (emit_elf_data_import_symbols buffer imports (wrap+ index 1)
                                          count name_offset)))))

(defun emit_elf_data_import_names (buffer imports index count)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_import) imports)
           (type usize index count) (returns c-int))
  (if (= index count) 1
      (let ((entry (pointer+ imports (wrap-cast isize index))))
        (if (= (native_data_emitted_p entry) 1)
            (progn
              (emit_source_bytes buffer (deref (field-pointer entry 'name))
                                 (deref (field-pointer entry 'name_length)))
              (emit_byte_unchecked buffer 0)
              (emit_elf_data_import_names buffer imports (wrap+ index 1) count))
            (emit_elf_data_import_names buffer imports (wrap+ index 1) count)))))

(defun elf_compiled_data_start (code_size imports import_count)
  (declare (type usize code_size import_count)
           (type (ptr native_data_import) imports) (returns usize))
  (compiled_data_align_up (wrap+ 64 code_size)
                          (defined_data_max_alignment imports import_count)))

(defun elf_compiled_relocation_start (code_size imports import_count)
  (declare (type usize code_size import_count)
           (type (ptr native_data_import) imports) (returns usize))
  (align8 (wrap+ (elf_compiled_data_start code_size imports import_count)
                 (defined_data_size imports import_count))))

(defun elf_compiled_section_offset (code_size imports import_count symbol_count
                                    name_bytes relocation_bytes)
  (declare (type usize code_size import_count symbol_count name_bytes
                       relocation_bytes)
           (type (ptr native_data_import) imports) (returns usize))
  (let ((symbol_offset
         (wrap+ (elf_compiled_relocation_start code_size imports import_count)
                relocation_bytes)))
    (align8
     (wrap+ (wrap+ symbol_offset (wrap* (wrap+ symbol_count 3) 24))
            (wrap+ name_bytes 66)))))

(defun emit_elf_import_data_headers (buffer code_size functions function_count
                                     imports import_count
                                     symbol_count name_bytes relocation_bytes
                                     output_target data_labels)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_function) functions)
           (type (ptr native_data_import) imports)
           (type usize code_size function_count import_count symbol_count
                       name_bytes relocation_bytes data_labels)
           (type u32 output_target)
           (returns c-int))
  (let ((data_offset (elf_compiled_data_start code_size imports import_count))
        (data_size (defined_data_size imports import_count))
        (data_alignment (defined_data_max_alignment imports import_count))
        (symbol_offset
         (wrap+ (elf_compiled_relocation_start code_size imports import_count)
                relocation_bytes))
        (symbol_bytes (wrap* (wrap+ symbol_count 3) 24)))
    (let ((name_offset (wrap+ symbol_offset symbol_bytes)))
      (let ((section_names (wrap+ name_offset name_bytes)))
        (emit_zero_until buffer (wrap+ (deref (field-pointer buffer 'length)) 64))
        (emit_section_header buffer 1 1 6 64 (wrap-cast u64 code_size) 0 0 16 0)
        (emit_section_header buffer 7 1 3 (wrap-cast u64 data_offset)
                             (wrap-cast u64 data_size) 0 0
                             (wrap-cast u64 data_alignment) 0)
        (emit_section_header buffer 13 4 0
                             (wrap-cast u64
                                        (elf_compiled_relocation_start
                                         code_size imports import_count))
                             (wrap-cast u64 relocation_bytes) 4 1 8 24)
        (emit_section_header buffer 24 2 0 (wrap-cast u64 symbol_offset)
                             (wrap-cast u64 symbol_bytes) 5
                             (wrap-cast u64
                              (wrap+ (wrap+ (wrap+ 3
                                                   (elf_mapping_symbol_count output_target))
                                            data_labels)
                                     (local_function_count_from
                                      functions 0 function_count))) 8 24)
        (emit_section_header buffer 32 3 0 (wrap-cast u64 name_offset)
                             (wrap-cast u64 name_bytes) 0 0 1 0)
        (emit_section_header buffer 40 3 0 (wrap-cast u64 section_names)
                             66 0 0 1 0)
        (emit_section_header buffer 50 1 0
                             (wrap-cast u64 (wrap+ section_names 66))
                             0 0 0 1 0)))))

(defun emit_elf64_calls_data (output_target code code_size functions function_count calls
                              imports import_count data_fixups buffer)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) calls data_fixups)
           (type (ptr native_data_import) imports)
           (type (ptr byte_buffer) buffer)
           (type usize code_size function_count import_count)
           (type u32 output_target) (returns c-int))
  (let ((data_symbols (data_import_emitted_count_from imports 0 import_count))
        (function_symbols (multi_function_count_from functions 0 function_count))
        (data_labels (elf_data_label_count data_fixups output_target))
        (name_bytes
         (wrap+ (wrap+ (multi_name_bytes functions function_count)
                       (wrap* (elf_mapping_symbol_count output_target) 3))
                (data_import_name_bytes_from imports 0 import_count)))
        (relocation_bytes
         (wrap* 24
                (wrap+ (elf_import_call_count functions calls 0)
                       (wrap* (if (= output_target 0) (wrap-cast usize 1)
                                  (wrap-cast usize 2))
                              (deref (field-pointer data_fixups 'count)))))))
    (let ((symbol_count (wrap+ (wrap+ (wrap+ function_symbols data_symbols)
                                      (elf_mapping_symbol_count output_target))
                               data_labels)))
      (let ((section_offset
             (elf_compiled_section_offset
              code_size imports import_count symbol_count name_bytes
              relocation_bytes)))
        (if (= (room_for buffer (wrap+ section_offset 512)) 0) 0
            (progn
              (emit_elf_header buffer section_offset
                               (native_target_elf_machine output_target)
                               (native_target_elf_flags output_target))
              (emit_source_bytes buffer code code_size)
              (emit_zero_until
               buffer (elf_compiled_data_start code_size imports import_count))
              (emit_defined_data_from
               buffer imports 0 import_count
               (elf_compiled_data_start code_size imports import_count))
              (emit_zero_until
               buffer (elf_compiled_relocation_start
                       code_size imports import_count))
              (emit_elf_call_relocations_with_data_labels
               buffer functions function_count calls 0 output_target data_labels)
              (emit_elf_data_import_relocations buffer functions function_count
                                                imports data_fixups 0 output_target)
              (emit_elf_calls_data_symbols buffer functions function_count data_fixups
                                           output_target)
              (emit_elf_data_import_symbols
               buffer imports 0 import_count
               (wrap+ (multi_name_bytes functions function_count)
                      (wrap* (elf_mapping_symbol_count output_target) 3)))
              (emit_elf_target_names buffer functions function_count output_target)
              (emit_elf_data_import_names buffer imports 0 import_count)
              (emit_section_names buffer)
              (emit_zero_until buffer (align8 (deref (field-pointer buffer 'length))))
              (emit_elf_import_data_headers buffer code_size functions function_count
                                            imports import_count
                                            symbol_count name_bytes relocation_bytes
                                            output_target data_labels)))))))

(defun write_elf64_calls_data_target (output_target code code_size functions function_count calls
                                      imports import_count data_fixups buffer)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) calls data_fixups)
           (type (ptr native_data_import) imports)
           (type (ptr byte_buffer) buffer)
           (type usize code_size function_count import_count)
           (type u32 output_target)
           (returns c-int) (c-export :c))
  (if (= (native_target_object_format output_target) 2) 0
      (if (= (elf_calls_output_shape_p code_size functions function_count buffer) 0) 0
          (if (= (elf_calls_arena_p calls) 0) 0
              (if (= (elf_calls_arena_p data_fixups) 0) 0
                  (if (= (valid_data_imports_from imports 0 import_count) 0) 0
                      (if (= (elf_target_function_spans_p
                              functions function_count 0 output_target) 0) 0
                          (if (= (elf_calls_valid_from
                                  code code_size functions function_count calls 0
                                  output_target) 0) 0
                              (if (= (elf_import_references_p
                                      functions function_count calls 0) 0) 0
                                  (if (= (data_fixups_valid_from
                                          code code_size imports import_count
                                          data_fixups 0 output_target) 0) 0
                                      (if (= (data_import_references_valid_from
                                              imports import_count data_fixups 0) 0) 0
                                          (emit_elf64_calls_data
                                           output_target code code_size functions
                                           function_count calls imports import_count
                                           data_fixups buffer))))))))))))

(defun write_elf64_calls_data (code code_size functions function_count calls
                               imports import_count data_fixups buffer)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) calls data_fixups)
           (type (ptr native_data_import) imports)
           (type (ptr byte_buffer) buffer)
           (type usize code_size function_count import_count)
           (returns c-int) (c-export :c))
  (write_elf64_calls_data_target 0 code code_size functions function_count calls
                                 imports import_count data_fixups buffer))
