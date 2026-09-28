(include "coff64_validation.lisp")

(defun coff_functions_shape_p (code code_size functions count buffer)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr byte_buffer) buffer)
           (type usize code_size count) (returns c-int))
  (if (= count 0) 0
      (if (< 16777215 count) 0
          (if (< 2147481592 code_size) 0
              (if (< 0 (deref (field-pointer buffer 'length))) 0
                  (if (= (valid_function_names_p functions count) 0) 0
                      (if (= (valid_function_spans_p functions count code_size) 0) 0
                          (coff_function_metadata_from code functions 0 count))))))))

(defun coff_fixups_shape_p (code code_size functions count fixups)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups) (type usize code_size count) (returns c-int))
  (if (= (coff_fixup_arena_p fixups) 0) 0
      (if (= (coff_calls_valid_range code code_size functions count fixups 0
                                     (deref (field-pointer fixups 'count))) 0) 0
          (coff_import_references_from functions count fixups 0))))

(defun coff_object_shape_p (code_size functions count fixups buffer)
  (declare (type (ptr native_function) functions) (type (ptr native_fixup_arena) fixups)
           (type (ptr byte_buffer) buffer) (type usize code_size count) (returns c-int))
  (let ((definitions (coff_defined_count_from functions 0 count))
        (symbols (coff_emitted_count_from functions 0 count))
        (calls (coff_import_call_count_range functions fixups 0 (deref (field-pointer fixups 'count))))
        (names (coff_long_names_from functions 0 count))
        (xdata (coff_xdata_bytes_from functions 0 count)))
    (if (= definitions 0) 0
        (let ((size (coff_object_bytes code_size definitions xdata calls symbols names)))
          (if (< #xffffffff size) 0
              (room_for buffer size))))))

(defun coff_emit_object (code code_size functions count fixups buffer)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups) (type (ptr byte_buffer) buffer)
           (type usize code_size count) (returns c-int))
  (let ((definitions (coff_defined_count_from functions 0 count))
        (symbols (coff_emitted_count_from functions 0 count))
        (calls (coff_import_call_count_range functions fixups 0 (deref (field-pointer fixups 'count))))
        (names (coff_long_names_from functions 0 count))
        (xdata (coff_xdata_bytes_from functions 0 count)))
    (coff_emit_header buffer code_size definitions xdata calls symbols)
    (emit_source_bytes buffer code code_size)
    (emit_zero_until buffer (coff_pdata_offset code_size))
    (coff_emit_pdata_from buffer functions 0 count 0)
    (emit_zero_until buffer (coff_xdata_offset code_size definitions))
    (coff_emit_xdata_from buffer functions 0 count)
    (emit_zero_until buffer (coff_text_relocation_offset code_size definitions xdata))
    (coff_emit_overflow_relocation buffer calls)
    (coff_emit_text_relocations_range buffer functions fixups 0
                                      (deref (field-pointer fixups 'count)))
    (emit_zero_until buffer (coff_pdata_relocation_offset code_size definitions xdata calls))
    (coff_emit_overflow_relocation buffer (wrap* 3 definitions))
    (coff_emit_pdata_relocations_from buffer functions 0 count 0)
    (emit_zero_until buffer (coff_symbol_offset code_size definitions xdata calls))
    (coff_emit_symbols buffer functions count names)
    (if (= (deref (field-pointer buffer 'length))
           (coff_object_bytes code_size definitions xdata calls symbols names)) 1 0)))

(defun write_coff64_calls (code code_size functions count fixups buffer)
  (declare (type (ptr u8) code) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups) (type (ptr byte_buffer) buffer)
           (type usize code_size count) (returns c-int) (c-export :c))
  (if (= (coff_functions_shape_p code code_size functions count buffer) 0) 0
      (if (= (coff_fixups_shape_p code code_size functions count fixups) 0) 0
          (if (= (coff_object_shape_p code_size functions count fixups buffer) 0) 0
              (coff_emit_object code code_size functions count fixups buffer)))))
