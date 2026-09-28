(include "coff64_sections.lisp")
(include "../backend/fixups.lisp")

(defun coff_emit_relocation (buffer field symbol kind)
  (declare (type (ptr byte_buffer) buffer) (type usize field symbol)
           (type u16 kind) (returns c-int))
  (emit_integer buffer (wrap-cast u64 field) 4)
  (emit_integer buffer (wrap-cast u64 symbol) 4)
  (emit_integer buffer (wrap-cast u64 kind) 2))

(defun coff_emit_overflow_relocation (buffer count)
  (declare (type (ptr byte_buffer) buffer) (type usize count) (returns c-int))
  (if (< 65535 count)
      (coff_emit_relocation buffer (wrap+ count 1) 0 0)
      1))

(defun coff_emit_text_relocation (buffer functions entry)
  (declare (type (ptr byte_buffer) buffer) (type (ptr native_function) functions)
           (type (ptr native_call_fixup) entry) (returns c-int))
  (if (= (deref (field-pointer
                (native_function_at functions (wrap- (deref (field-pointer entry 'target)) 1))
                'imported)) 1)
      (coff_emit_relocation buffer
        (wrap+ (deref (field-pointer entry 'instruction)) 1)
        (coff_symbol_index_from functions
          (wrap- (deref (field-pointer entry 'target)) 1) 0 0) 4)
      1))

(defun coff_emit_text_relocations_range (buffer functions fixups first last)
  (declare (type (ptr byte_buffer) buffer) (type (ptr native_function) functions)
           (type (ptr native_fixup_arena) fixups) (type usize first last) (returns c-int))
  (if (= first last) 1
      (if (= (wrap+ first 1) last)
          (coff_emit_text_relocation buffer functions (call_fixup_at fixups first))
          (let ((middle (wrap+ first (wrap-cast usize
                                 (shr64 (wrap-cast u64 (wrap- last first)) 1)))))
            (if (= (coff_emit_text_relocations_range buffer functions fixups first middle) 0) 0
                (coff_emit_text_relocations_range buffer functions fixups middle last))))))

(defun coff_emit_pdata_relocations_from (buffer functions index count rank)
  (declare (type (ptr byte_buffer) buffer) (type (ptr native_function) functions)
           (type usize index count rank) (returns c-int))
  (if (= index count) 1
      (let ((entry (native_function_at functions index)))
        (if (= (deref (field-pointer entry 'imported)) 1)
            (coff_emit_pdata_relocations_from buffer functions (wrap+ index 1) count rank)
            (let ((field (wrap* 12 rank))
                  (symbol (coff_symbol_index_from functions index 0 0)))
              (coff_emit_relocation buffer field symbol 3)
              (coff_emit_relocation buffer (wrap+ field 4) symbol 3)
              (coff_emit_relocation buffer (wrap+ field 8) 3 3)
              (coff_emit_pdata_relocations_from buffer functions
                (wrap+ index 1) count (wrap+ rank 1)))))))
