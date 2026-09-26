(include "../binary.lisp")

;; First native ELF writer slice: one exported function, no data or
;; relocations. The section and symbol layout matches the Stage 0 ELF writer.

(defun align8 (value)
  (declare (type usize value) (returns usize))
  (bits-and (wrap+ value 7) (wrap- 0 8)))

(defun section_header_offset (code_size name_size)
  (declare (type usize code_size name_size) (returns usize))
  (let ((symtab (align8 (wrap+ 64 code_size))))
    (align8 (wrap+ (wrap+ symtab name_size) 164))))

(defun single_object_size (code_size name_size)
  (declare (type usize code_size name_size) (returns usize))
  (wrap+ (section_header_offset code_size name_size) 512))

(defun name_ascii_p (name index length)
  (declare (type (ptr u8) name)
           (type usize index length)
           (returns c-int))
  (if (= index length)
      1
      (let ((byte (deref (pointer+ name (wrap-cast isize index)))))
        (if (= byte 0)
            0
            (if (< byte 128)
                (name_ascii_p name (wrap+ index 1) length)
                0)))))

(defun emit_zero_until (buffer stop)
  (declare (type (ptr byte_buffer) buffer)
           (type usize stop)
           (returns c-int))
  (while (< (deref (field-pointer buffer 'length)) stop)
    (emit_byte_unchecked buffer 0))
  1)

(defun emit_source_bytes (buffer source length)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr u8) source)
           (type usize length)
           (returns c-int))
  (let ((start (deref (field-pointer buffer 'length))))
    (while (< (deref (field-pointer buffer 'length))
              (wrap+ start length))
      (let ((index (wrap- (deref (field-pointer buffer 'length)) start)))
        (emit_byte_unchecked
         buffer (deref (pointer+ source (wrap-cast isize index)))))))
  1)

(defun emit_elf_header (buffer section_offset machine flags)
  (declare (type (ptr byte_buffer) buffer)
           (type usize section_offset)
           (type u16 machine)
           (type u32 flags)
           (returns c-int))
  (emit_integer buffer #x464c457f 4) ; ELF magic
  (emit_integer buffer #x0000000000010102 8) ; 64-bit little-endian ELF
  (emit_integer buffer 0 4)
  (emit_integer buffer 1 2) ; ET_REL
  (emit_integer buffer (wrap-cast u64 machine) 2)
  (emit_integer buffer 1 4)
  (emit_integer buffer 0 8) ; entry
  (emit_integer buffer 0 8) ; program headers
  (emit_integer buffer (wrap-cast u64 section_offset) 8)
  (emit_integer buffer (wrap-cast u64 flags) 4)
  (emit_integer buffer 64 2) ; ELF header size
  (emit_integer buffer 0 2) ; program header size
  (emit_integer buffer 0 2) ; program header count
  (emit_integer buffer 64 2) ; section header size
  (emit_integer buffer 8 2) ; section count
  (emit_integer buffer 6 2) ; .shstrtab index
  1)

(defun emit_symbol (buffer name info section value size)
  (declare (type (ptr byte_buffer) buffer)
           (type u64 name info section value size)
           (returns c-int))
  (emit_integer buffer name 4)
  (emit_integer buffer info 1)
  (emit_integer buffer 0 1)
  (emit_integer buffer section 2)
  (emit_integer buffer value 8)
  (emit_integer buffer size 8)
  1)

(defun emit_symbol_table (buffer code_size)
  (declare (type (ptr byte_buffer) buffer)
           (type usize code_size)
           (returns c-int))
  (emit_symbol buffer 0 0 0 0 0)
  (emit_symbol buffer 0 3 1 0 0)
  (emit_symbol buffer 0 3 2 0 0)
  (emit_symbol buffer 1 18 1 0 (wrap-cast u64 code_size))
  1)

(defun emit_section_names (buffer)
  (declare (type (ptr byte_buffer) buffer) (returns c-int))
  (emit_byte_unchecked buffer 0)
  (emit_integer buffer #x747865742e 5) ; .text
  (emit_byte_unchecked buffer 0)
  (emit_integer buffer #x617461642e 5) ; .data
  (emit_byte_unchecked buffer 0)
  (emit_integer buffer #x65742e616c65722e 8) ; .rela.te
  (emit_integer buffer #x7478 2) ; xt
  (emit_byte_unchecked buffer 0)
  (emit_integer buffer #x6261746d79732e 7) ; .symtab
  (emit_byte_unchecked buffer 0)
  (emit_integer buffer #x6261747274732e 7) ; .strtab
  (emit_byte_unchecked buffer 0)
  (emit_integer buffer #x617472747368732e 8) ; .shstrta
  (emit_integer buffer #x62 1) ; b
  (emit_byte_unchecked buffer 0)
  (emit_integer buffer #x4e472e65746f6e2e 8) ; .note.GN
  (emit_integer buffer #x6b636174732d55 7) ; U-stack
  (emit_byte_unchecked buffer 0)
  1)

(defun emit_section_header (buffer name kind flags offset size link info
                            alignment entry_size)
  (declare (type (ptr byte_buffer) buffer)
           (type u64 name kind flags offset size link info alignment
                 entry_size)
           (returns c-int))
  (emit_integer buffer name 4)
  (emit_integer buffer kind 4)
  (emit_integer buffer flags 8)
  (emit_integer buffer 0 8) ; address in a relocatable object
  (emit_integer buffer offset 8)
  (emit_integer buffer size 8)
  (emit_integer buffer link 4)
  (emit_integer buffer info 4)
  (emit_integer buffer alignment 8)
  (emit_integer buffer entry_size 8)
  1)

(defun emit_section_headers (buffer code_size name_size)
  (declare (type (ptr byte_buffer) buffer)
           (type usize code_size name_size)
           (returns c-int))
  (let ((data_offset (wrap+ 64 code_size))
        (symtab_offset (align8 (wrap+ 64 code_size))))
    (let ((strtab_offset (wrap+ symtab_offset 96)))
      (let ((shstr_offset (wrap+ (wrap+ strtab_offset name_size) 2)))
        (let ((note_offset (wrap+ shstr_offset 66)))
          (emit_zero_until buffer (wrap+ (deref (field-pointer buffer 'length))
                                        64)) ; null section header
          (emit_section_header buffer 1 1 6 64
                               (wrap-cast u64 code_size) 0 0 16 0)
          (emit_section_header buffer 7 1 3
                               (wrap-cast u64 data_offset) 0 0 0 1 0)
          (emit_section_header buffer 13 4 0
                               (wrap-cast u64 symtab_offset) 0 4 1 8 24)
          (emit_section_header buffer 24 2 0
                               (wrap-cast u64 symtab_offset) 96 5 3 8 24)
          (emit_section_header buffer 32 3 0
                               (wrap-cast u64 strtab_offset)
                               (wrap-cast u64 (wrap+ name_size 2)) 0 0 1 0)
          (emit_section_header buffer 40 3 0
                               (wrap-cast u64 shstr_offset) 66 0 0 1 0)
          (emit_section_header buffer 50 1 0
                               (wrap-cast u64 note_offset) 0 0 0 1 0)
          1)))))

(defun emit_object_sections (buffer code code_size name name_size)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr u8) code name)
           (type usize code_size name_size)
           (returns c-int))
  (emit_source_bytes buffer code code_size)
  (emit_zero_until buffer (align8 (deref (field-pointer buffer 'length))))
  (emit_symbol_table buffer code_size)
  (emit_byte_unchecked buffer 0)
  (emit_source_bytes buffer name name_size)
  (emit_byte_unchecked buffer 0)
  (emit_section_names buffer)
  (emit_zero_until buffer (align8 (deref (field-pointer buffer 'length))))
  (emit_section_headers buffer code_size name_size))

(defun write_elf64_single (machine flags code code_size name name_size buffer)
  (declare (type u16 machine)
           (type u32 flags)
           (type (ptr u8) code name)
           (type usize code_size name_size)
           (type (ptr byte_buffer) buffer)
           (returns c-int)
           (c-export :c))
  (if (< 1048576 code_size)
      0
      (if (= name_size 0)
          0
          (if (< 255 name_size)
              0
              (if (= (name_ascii_p name 0 name_size) 0)
                  0
                  (if (= (deref (field-pointer buffer 'length)) 0)
                      (if (= (room_for buffer
                                       (single_object_size code_size
                                                           name_size)) 1)
                          (progn
                            (emit_elf_header
                             buffer
                             (section_header_offset code_size name_size)
                             machine flags)
                            (emit_object_sections buffer code code_size name
                                                  name_size))
                          0)
                      0))))))
