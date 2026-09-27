(include "../target.lisp")
(include "../binary.lisp")
(include "../backend/fixups.lisp")

;; Instruction spans and relocation fields are target contracts. The object
;; writer validates encoded calls but does not emit CPU instructions.
(defun elf_call_width (target)
  (declare (type u32 target) (returns usize))
  (if (= target 2) 8 (if (= target 0) (wrap-cast usize 5) (wrap-cast usize 4))))

(defun elf_call_field_offset (target)
  (declare (type u32 target) (returns usize))
  (if (= (native_target_architecture target) 1) 1 (wrap-cast usize 0)))

(defun elf_call_relocation_type (target)
  (declare (type u32 target) (returns u64))
  (if (= target 2) 19 (if (= target 0) (wrap-cast u64 4) (wrap-cast u64 283))))

(defun elf_call_addend (target)
  (declare (type u32 target) (returns u64))
  (if (= (native_target_architecture target) 1) (wrap- 0 4) (wrap-cast u64 0)))

(defun elf_mapping_symbol_count (target)
  (declare (type u32 target) (returns usize))
  (if (= (native_target_architecture target) 2) 1 (wrap-cast usize 0)))

(defun elf_rv_encoded_call_p (data imported)
  (declare (type (ptr u8) data) (type usize imported) (returns c-int))
  (let ((high (read_u32_le data)) (low (read_u32_le (pointer+ data 4))))
    (if (= (bits-and high #xfff) #x97)
        (if (= (bits-and low #xfffff) #x80e7)
            (if (= imported 1) (if (= high #x97) (if (= low #x80e7) 1 0) 0) 1) 0) 0)))

(defun elf_a64_encoded_call_p (data imported)
  (declare (type (ptr u8) data) (type usize imported) (returns c-int))
  (let ((word (read_u32_le data)))
    (if (= (bits-and word #xfc000000) #x94000000)
        (if (= imported 1) (if (= word #x94000000) 1 0) 1) 0)))

(defun elf_encoded_call_p (code position target imported)
  (declare (type (ptr u8) code) (type usize position imported) (type u32 target) (returns c-int))
  (let ((data (pointer+ code (wrap-cast isize position))))
    (if (= target 0)
        (if (= (deref data) #xe8)
            (if (= imported 1) (if (= (read_u32_le (pointer+ data 1)) 0) 1 0) 1) 0)
        (if (= (bits-and position 3) 0)
            (if (= target 1) (elf_a64_encoded_call_p data imported)
                (elf_rv_encoded_call_p data imported)) 0))))

(defun elf_target_function_spans_p (functions count index target)
  (declare (type (ptr native_function) functions) (type usize count index) (type u32 target)
           (returns c-int))
  (if (= (native_target_architecture target) 1) 1
      (if (= index count) 1
          (let ((function (native_function_at functions index)))
            (if (= (bits-and (deref (field-pointer function 'offset)) 3) 0)
                (if (= (bits-and (deref (field-pointer function 'size)) 3) 0)
                    (elf_target_function_spans_p functions count (wrap+ index 1) target) 0) 0)))))

(defun emit_elf_target_symbols (buffer functions count target)
  (declare (type (ptr byte_buffer) buffer) (type (ptr native_function) functions)
           (type usize count) (type u32 target) (returns c-int))
  (emit_symbol buffer 0 0 0 0 0)
  (emit_symbol buffer 0 3 1 0 0)
  (emit_symbol buffer 0 3 2 0 0)
  (if (= (elf_mapping_symbol_count target) 1) (emit_symbol buffer 1 0 1 0 0) (wrap-cast c-int 1))
  (let ((next (emit_selected_symbols_from buffer functions 0 count
                   (wrap+ 1 (wrap* (elf_mapping_symbol_count target) 3)) 0)))
    (emit_selected_symbols_from buffer functions 0 count next 1))
  1)

(defun emit_elf_target_names (buffer functions count target)
  (declare (type (ptr byte_buffer) buffer) (type (ptr native_function) functions)
           (type usize count) (type u32 target) (returns c-int))
  (emit_byte_unchecked buffer 0)
  (if (= (elf_mapping_symbol_count target) 1) (emit_integer buffer #x7824 3) (wrap-cast c-int 1))
  (emit_selected_names_from buffer functions 0 count 0)
  (emit_selected_names_from buffer functions 0 count 1))
