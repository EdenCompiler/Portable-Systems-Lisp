(include "coff64_symbols.lisp")

(defun coff_relocation_header_count (count)
  (declare (type usize count) (returns usize))
  (if (< 65535 count) 65535 count))

(defun coff_section_flags (flags relocations)
  (declare (type u32 flags) (type usize relocations) (returns u32))
  (if (< 65535 relocations) (wrap+ flags #x01000000) flags))

(defun coff_emit_section_header (buffer name size data_offset reloc_offset relocations flags)
  (declare (type (ptr byte_buffer) buffer) (type u64 name)
           (type usize size data_offset reloc_offset relocations) (type u32 flags)
           (returns c-int))
  (emit_integer buffer name 8)
  (emit_integer buffer 0 8)
  (emit_integer buffer (wrap-cast u64 size) 4)
  (emit_integer buffer (wrap-cast u64 data_offset) 4)
  (emit_integer buffer (wrap-cast u64 reloc_offset) 4)
  (emit_integer buffer 0 4)
  (emit_integer buffer (wrap-cast u64 (coff_relocation_header_count relocations)) 2)
  (emit_integer buffer 0 2)
  (emit_integer buffer (wrap-cast u64 (coff_section_flags flags relocations)) 4))

(defun coff_emit_header (buffer code_size definitions xdata_size calls symbols)
  (declare (type (ptr byte_buffer) buffer)
           (type usize code_size definitions xdata_size calls symbols) (returns c-int))
  (emit_integer buffer #x8664 2) ; AMD64
  (emit_integer buffer 4 2)
  (emit_integer buffer 0 4) ; reproducible timestamp
  (emit_integer buffer (wrap-cast u64 (coff_symbol_offset code_size definitions xdata_size calls)) 4)
  (emit_integer buffer (wrap-cast u64 (wrap+ 4 symbols)) 4)
  (emit_integer buffer 0 4) ; no optional header or file flags
  (coff_emit_section_header buffer #x747865742e code_size 180
    (if (= calls 0) (wrap-cast usize 0)
        (coff_text_relocation_offset code_size definitions xdata_size))
    calls #x60500020)
  (coff_emit_section_header buffer #x617461642e 0 0 0 0 #xc0500040)
  (coff_emit_section_header buffer #x61746164702e (wrap* 12 definitions)
    (coff_pdata_offset code_size)
    (coff_pdata_relocation_offset code_size definitions xdata_size calls)
    (wrap* 3 definitions) #x40300040)
  (coff_emit_section_header buffer #x61746164782e xdata_size
    (coff_xdata_offset code_size definitions) 0 0 #x40300040))

(defun coff_emit_pdata_from (buffer functions index count xdata_offset)
  (declare (type (ptr byte_buffer) buffer) (type (ptr native_function) functions)
           (type usize index count xdata_offset) (returns usize))
  (if (= index count) xdata_offset
      (let ((entry (native_function_at functions index)))
        (if (= (deref (field-pointer entry 'imported)) 1)
            (coff_emit_pdata_from buffer functions (wrap+ index 1) count xdata_offset)
            (progn
              (emit_integer buffer 0 4) ; begin + function ADDR32NB relocation
              (emit_integer buffer (wrap-cast u64 (deref (field-pointer entry 'size))) 4)
              (emit_integer buffer (wrap-cast u64 xdata_offset) 4)
              (coff_emit_pdata_from buffer functions (wrap+ index 1) count
                (wrap+ xdata_offset (win64_unwind_bytes (deref (field-pointer entry 'frame_size))))))))))

(defun coff_emit_xdata_from (buffer functions index count)
  (declare (type (ptr byte_buffer) buffer) (type (ptr native_function) functions)
           (type usize index count) (returns c-int))
  (if (= index count) 1
      (let ((entry (native_function_at functions index)))
        (if (= (deref (field-pointer entry 'imported)) 1)
            (coff_emit_xdata_from buffer functions (wrap+ index 1) count)
            (if (= (win64_write_unwind buffer
                     (deref (field-pointer entry 'frame_size))
                     (deref (field-pointer entry 'prologue_size))) 0) 0
                (coff_emit_xdata_from buffer functions (wrap+ index 1) count))))))
