(include "coff64_calls.lisp")

(defun coff_data_long_names_from (imports index count)
  (declare (type (ptr native_data_import) imports)
           (type usize index count) (returns usize))
  (if (= index count) 0
      (let ((entry (pointer+ imports (wrap-cast isize index))))
        (wrap+ (if (= (deref (field-pointer entry 'referenced)) 1)
                   (if (< 8 (deref (field-pointer entry 'name_length)))
                       (wrap+ (deref (field-pointer entry 'name_length)) 1)
                       (wrap-cast usize 0))
                   (wrap-cast usize 0))
               (coff_data_long_names_from imports (wrap+ index 1) count)))))

(defun coff_data_symbol_index (functions function_count imports target)
  (declare (type (ptr native_function) functions)
           (type (ptr native_data_import) imports)
           (type usize function_count target) (returns usize))
  (wrap+ (wrap+ 4 (coff_emitted_count_from functions 0 function_count))
         (data_import_rank_from imports (wrap- target 1) 0 0)))

(defun coff_data_fixup_valid_p (code code_size imports import_count fixup)
  (declare (type (ptr u8) code) (type (ptr native_data_import) imports)
           (type (ptr native_call_fixup) fixup)
           (type usize code_size import_count) (returns c-int))
  (let ((target (deref (field-pointer fixup 'target)))
        (position (deref (field-pointer fixup 'instruction))))
    (if (= target 0) 0
        (if (< import_count target) 0
            (if (< code_size 7) 0
                (if (< (wrap- code_size 7) position) 0
                    (let ((bytes (pointer+ code (wrap-cast isize position)))
                          (entry (pointer+ imports
                                           (wrap-cast isize (wrap- target 1)))))
                      (if (= (deref (field-pointer entry 'referenced)) 0) 0
                          (if (= (deref bytes) #x48)
                              (if (= (deref (pointer+ bytes 1)) #x8d)
                                  (if (= (deref (pointer+ bytes 2)) #x05)
                                      (if (= (read_u32_le (pointer+ bytes 3)) 0) 1 0)
                                      0)
                                  0)
                              0)))))))))

(defun coff_data_fixups_valid_from (code code_size imports import_count fixups index)
  (declare (type (ptr u8) code) (type (ptr native_data_import) imports)
           (type (ptr native_fixup_arena) fixups)
           (type usize code_size import_count index) (returns c-int))
  (if (= index (deref (field-pointer fixups 'count))) 1
      (if (= (data_fixup_order_p fixups index 7) 0) 0
          (if (= (coff_data_fixup_valid_p code code_size imports import_count
                                          (call_fixup_at fixups index)) 0) 0
              (coff_data_fixups_valid_from code code_size imports import_count
                                           fixups (wrap+ index 1))))))

(defun coff_emit_data_relocations (buffer functions function_count imports fixups index)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_function) functions)
           (type (ptr native_data_import) imports)
           (type (ptr native_fixup_arena) fixups)
           (type usize function_count index) (returns c-int))
  (if (= index (deref (field-pointer fixups 'count))) 1
      (let ((fixup (call_fixup_at fixups index)))
        (coff_emit_relocation
         buffer (wrap+ (deref (field-pointer fixup 'instruction)) 3)
         (coff_data_symbol_index functions function_count imports
                                 (deref (field-pointer fixup 'target))) 4)
        (coff_emit_data_relocations buffer functions function_count imports
                                    fixups (wrap+ index 1)))))

(defun coff_emit_data_symbol_name (buffer entry string_offset)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_import) entry)
           (type usize string_offset) (returns c-int))
  (let ((length (deref (field-pointer entry 'name_length))))
    (if (< 8 length)
        (progn (emit_integer buffer 0 4)
               (emit_integer buffer (wrap-cast u64 string_offset) 4))
        (coff_emit_short_name buffer (deref (field-pointer entry 'name)) length))))

(defun coff_emit_data_symbols_from (buffer imports index count string_offset)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_import) imports)
           (type usize index count string_offset) (returns usize))
  (if (= index count) string_offset
      (let ((entry (pointer+ imports (wrap-cast isize index))))
        (if (= (deref (field-pointer entry 'referenced)) 1)
            (progn
              (coff_emit_data_symbol_name buffer entry string_offset)
              (coff_emit_symbol_record buffer 0 0 0 2)
              (coff_emit_data_symbols_from
               buffer imports (wrap+ index 1) count
               (if (< 8 (deref (field-pointer entry 'name_length)))
                   (wrap+ string_offset
                          (wrap+ (deref (field-pointer entry 'name_length)) 1))
                   string_offset)))
            (coff_emit_data_symbols_from buffer imports (wrap+ index 1)
                                         count string_offset)))))

(defun coff_emit_data_long_names (buffer imports index count)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_import) imports)
           (type usize index count) (returns c-int))
  (if (= index count) 1
      (let ((entry (pointer+ imports (wrap-cast isize index))))
        (if (= (deref (field-pointer entry 'referenced)) 1)
            (if (< 8 (deref (field-pointer entry 'name_length)))
                (progn
                  (emit_source_bytes buffer (deref (field-pointer entry 'name))
                                     (deref (field-pointer entry 'name_length)))
                  (emit_byte buffer 0))
                (wrap-cast c-int 1))
            (wrap-cast c-int 1))
        (coff_emit_data_long_names buffer imports (wrap+ index 1) count))))

(defun coff_emit_symbols_with_data (buffer functions function_count imports
                                    import_count function_long_names)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_function) functions)
           (type (ptr native_data_import) imports)
           (type usize function_count import_count function_long_names)
           (returns c-int))
  (coff_emit_section_symbols buffer)
  (coff_emit_function_symbols_from buffer functions 0 function_count 4)
  (coff_emit_data_symbols_from buffer imports 0 import_count
                               (wrap+ 4 function_long_names))
  (let ((long_names (wrap+ function_long_names
                            (coff_data_long_names_from imports 0 import_count))))
    (emit_integer buffer (wrap-cast u64 (wrap+ 4 long_names)) 4))
  (coff_emit_long_names_from buffer functions 0 function_count)
  (coff_emit_data_long_names buffer imports 0 import_count))

(defun coff_emit_object_with_data (code code_size functions function_count calls
                                   imports import_count data_fixups buffer)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) calls data_fixups)
           (type (ptr native_data_import) imports)
           (type (ptr byte_buffer) buffer)
           (type usize code_size function_count import_count) (returns c-int))
  (let ((definitions (coff_defined_count_from functions 0 function_count))
        (function_symbols (coff_emitted_count_from functions 0 function_count))
        (data_symbols (data_import_emitted_count_from imports 0 import_count))
        (function_names (coff_long_names_from functions 0 function_count))
        (data_names (coff_data_long_names_from imports 0 import_count))
        (xdata (coff_xdata_bytes_from functions 0 function_count))
        (relocations
         (wrap+ (coff_import_call_count_range functions calls 0
                                               (deref (field-pointer calls 'count)))
                (deref (field-pointer data_fixups 'count)))))
    (let ((symbols (wrap+ function_symbols data_symbols))
          (names (wrap+ function_names data_names)))
      (coff_emit_header buffer code_size definitions xdata relocations symbols)
      (emit_source_bytes buffer code code_size)
      (emit_zero_until buffer (coff_pdata_offset code_size))
      (coff_emit_pdata_from buffer functions 0 function_count 0)
      (emit_zero_until buffer (coff_xdata_offset code_size definitions))
      (coff_emit_xdata_from buffer functions 0 function_count)
      (emit_zero_until buffer
                       (coff_text_relocation_offset code_size definitions xdata))
      (coff_emit_overflow_relocation buffer relocations)
      (coff_emit_text_relocations_range buffer functions calls 0
                                        (deref (field-pointer calls 'count)))
      (coff_emit_data_relocations buffer functions function_count imports
                                  data_fixups 0)
      (emit_zero_until buffer
                       (coff_pdata_relocation_offset code_size definitions
                                                     xdata relocations))
      (coff_emit_overflow_relocation buffer (wrap* 3 definitions))
      (coff_emit_pdata_relocations_from buffer functions 0 function_count 0)
      (emit_zero_until buffer
                       (coff_symbol_offset code_size definitions xdata relocations))
      (coff_emit_symbols_with_data buffer functions function_count imports
                                   import_count function_names)
      (if (= (deref (field-pointer buffer 'length))
             (coff_object_bytes code_size definitions xdata relocations
                                symbols names)) 1 0))))

(defun write_coff64_calls_data (code code_size functions function_count calls
                                imports import_count data_fixups buffer)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) calls data_fixups)
           (type (ptr native_data_import) imports)
           (type (ptr byte_buffer) buffer)
           (type usize code_size function_count import_count)
           (returns c-int) (c-export :c))
  (if (= (coff_functions_shape_p code code_size functions function_count buffer) 0) 0
      (if (= (coff_fixups_shape_p code code_size functions function_count calls) 0) 0
          (if (= (coff_fixup_arena_p data_fixups) 0) 0
              (if (= (valid_data_imports_from imports 0 import_count) 0) 0
                  (if (= (coff_data_fixups_valid_from code code_size imports import_count
                                                      data_fixups 0) 0) 0
                      (if (= (data_import_references_valid_from
                              imports import_count data_fixups 0) 0) 0
                          (let ((definitions (coff_defined_count_from
                                              functions 0 function_count))
                                (xdata (coff_xdata_bytes_from
                                        functions 0 function_count))
                                (relocations
                                 (wrap+ (coff_import_call_count_range
                                         functions calls 0
                                         (deref (field-pointer calls 'count)))
                                        (deref (field-pointer data_fixups 'count))))
                                (symbols
                                 (wrap+ (coff_emitted_count_from
                                         functions 0 function_count)
                                        (data_import_emitted_count_from
                                         imports 0 import_count)))
                                (names
                                 (wrap+ (coff_long_names_from
                                         functions 0 function_count)
                                        (coff_data_long_names_from
                                         imports 0 import_count))))
                            (let ((size (coff_object_bytes code_size definitions xdata
                                                          relocations symbols names)))
                              (if (< #xffffffff size) 0
                                  (if (= (room_for buffer size) 0) 0
                                      (coff_emit_object_with_data
                                       code code_size functions function_count calls
                                       imports import_count data_fixups buffer))))))))))))
