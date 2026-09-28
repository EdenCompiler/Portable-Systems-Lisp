(include "coff64_layout.lisp")
(include "bytes.lisp")

(defun coff_emit_short_name (buffer name length)
  (declare (type (ptr byte_buffer) buffer) (type (ptr u8) name)
           (type usize length) (returns c-int))
  (emit_source_bytes buffer name length)
  (emit_integer buffer 0 (wrap- 8 length)))

(defun coff_emit_symbol_record (buffer value section kind storage)
  (declare (type (ptr byte_buffer) buffer) (type usize value section)
           (type u16 kind) (type u8 storage) (returns c-int))
  (emit_integer buffer (wrap-cast u64 value) 4)
  (emit_integer buffer (wrap-cast u64 section) 2)
  (emit_integer buffer (wrap-cast u64 kind) 2)
  (emit_byte buffer storage)
  (emit_byte buffer 0))

(defun coff_emit_section_symbol (buffer name section)
  (declare (type (ptr byte_buffer) buffer) (type u64 name)
           (type usize section) (returns c-int))
  (emit_integer buffer name 8)
  (coff_emit_symbol_record buffer 0 section 0 3))

(defun coff_emit_section_symbols (buffer)
  (declare (type (ptr byte_buffer) buffer) (returns c-int))
  (coff_emit_section_symbol buffer #x747865742e 1) ; .text
  (coff_emit_section_symbol buffer #x617461642e 2) ; .data
  (coff_emit_section_symbol buffer #x61746164702e 3) ; .pdata
  (coff_emit_section_symbol buffer #x61746164782e 4)) ; .xdata

(defun coff_emit_function_symbol (buffer function string_offset)
  (declare (type (ptr byte_buffer) buffer) (type (ptr native_function) function)
           (type usize string_offset) (returns c-int))
  (let ((length (deref (field-pointer function 'name_length))))
    (if (< 8 length)
        (progn (emit_integer buffer 0 4)
               (emit_integer buffer (wrap-cast u64 string_offset) 4))
        (coff_emit_short_name buffer (deref (field-pointer function 'name)) length)))
  (if (= (deref (field-pointer function 'imported)) 1)
      (coff_emit_symbol_record buffer 0 0 #x20 2)
      (coff_emit_symbol_record buffer
        (deref (field-pointer function 'offset)) 1 #x20
        (if (= (deref (field-pointer function 'exported)) 1) 2 3))))

(defun coff_emit_function_symbols_from (buffer functions index count string_offset)
  (declare (type (ptr byte_buffer) buffer) (type (ptr native_function) functions)
           (type usize index count string_offset) (returns usize))
  (if (= index count) string_offset
      (let ((entry (native_function_at functions index)))
        (if (= (native_function_emitted_p entry) 1)
            (progn
              (coff_emit_function_symbol buffer entry string_offset)
              (coff_emit_function_symbols_from buffer functions (wrap+ index 1) count
                (if (< 8 (deref (field-pointer entry 'name_length)))
                    (wrap+ string_offset (wrap+ (deref (field-pointer entry 'name_length)) 1))
                    string_offset)))
            (coff_emit_function_symbols_from buffer functions (wrap+ index 1) count string_offset)))))

(defun coff_emit_long_names_from (buffer functions index count)
  (declare (type (ptr byte_buffer) buffer) (type (ptr native_function) functions)
           (type usize index count) (returns c-int))
  (if (= index count) 1
      (let ((entry (native_function_at functions index)))
        (if (= (native_function_emitted_p entry) 1)
            (if (< 8 (deref (field-pointer entry 'name_length)))
                (progn
                  (emit_source_bytes buffer (deref (field-pointer entry 'name))
                                     (deref (field-pointer entry 'name_length)))
                  (emit_byte buffer 0))
                (wrap-cast c-int 1))
            (wrap-cast c-int 1))
        (coff_emit_long_names_from buffer functions (wrap+ index 1) count))))

(defun coff_symbol_index_from (functions target index rank)
  (declare (type (ptr native_function) functions) (type usize target index rank) (returns usize))
  (if (= index target) (wrap+ 4 rank)
      (coff_symbol_index_from functions target (wrap+ index 1)
        (wrap+ rank (native_function_emitted_p (native_function_at functions index))))))

(defun coff_emit_symbols (buffer functions count long_names)
  (declare (type (ptr byte_buffer) buffer) (type (ptr native_function) functions)
           (type usize count long_names) (returns c-int))
  (coff_emit_section_symbols buffer)
  (coff_emit_function_symbols_from buffer functions 0 count 4)
  (emit_integer buffer (wrap-cast u64 (wrap+ 4 long_names)) 4)
  (coff_emit_long_names_from buffer functions 0 count))
