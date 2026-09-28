(include "elf64.lisp")
(include "data_validation.lisp")

;; Data-only objects establish the native bootstrap's byte, alignment, and
;; symbol model before code-to-data relocations are added to the compiler.

(defun emit_native_data_from (buffer symbols index count)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_symbol) symbols)
           (type usize index count) (returns c-int))
  (if (= index count) 1
      (let ((symbol (native_data_at symbols index)))
        (emit_zero_until
         buffer
         (native_align_up
          (deref (field-pointer buffer 'length))
          (deref (field-pointer symbol 'alignment))))
        (emit_source_bytes buffer
                           (deref (field-pointer symbol 'bytes))
                           (deref (field-pointer symbol 'size)))
        (emit_native_data_from buffer symbols (wrap+ index 1) count))))

(defun emit_selected_data_symbols (buffer symbols index count name_offset selected)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_symbol) symbols)
           (type usize index count name_offset) (type u8 selected) (returns usize))
  (if (= index count) name_offset
      (let ((symbol (native_data_at symbols index)))
        (if (= (deref (field-pointer symbol 'exported)) selected)
            (progn
              (emit_symbol buffer (wrap-cast u64 name_offset)
                           (if (= selected 1) 17 1) 2
                           (wrap-cast u64 (native_data_offset symbols index))
                           (wrap-cast u64 (deref (field-pointer symbol 'size))))
              (emit_selected_data_symbols
               buffer symbols (wrap+ index 1) count
               (wrap+ name_offset
                      (wrap+ (deref (field-pointer symbol 'name_length)) 1))
               selected))
            (emit_selected_data_symbols buffer symbols (wrap+ index 1) count
                                        name_offset selected)))))

(defun emit_static_elf_symbols (buffer symbols count)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_symbol) symbols)
           (type usize count) (returns c-int))
  (emit_symbol buffer 0 0 0 0 0)
  (emit_symbol buffer 0 3 1 0 0)
  (emit_symbol buffer 0 3 2 0 0)
  (let ((next (emit_selected_data_symbols buffer symbols 0 count 1 0)))
    (emit_selected_data_symbols buffer symbols 0 count next 1))
  1)

(defun emit_selected_data_names (buffer symbols index count selected)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_symbol) symbols)
           (type usize index count) (type u8 selected) (returns c-int))
  (if (= index count) 1
      (let ((symbol (native_data_at symbols index)))
        (if (= (deref (field-pointer symbol 'exported)) selected)
            (progn
              (emit_source_bytes buffer
                                 (deref (field-pointer symbol 'name))
                                 (deref (field-pointer symbol 'name_length)))
              (emit_byte_unchecked buffer 0)
              (emit_selected_data_names buffer symbols (wrap+ index 1)
                                        count selected))
            (emit_selected_data_names buffer symbols (wrap+ index 1)
                                      count selected)))))

(defun emit_static_data_names (buffer symbols count)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_symbol) symbols)
           (type usize count) (returns c-int))
  (emit_byte_unchecked buffer 0)
  (emit_selected_data_names buffer symbols 0 count 0)
  (emit_selected_data_names buffer symbols 0 count 1))

(defun static_elf_data_start (alignment)
  (declare (type usize alignment) (returns usize))
  (native_align_up 64 alignment))

(defun static_elf_symbol_offset (symbols count)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize count) (returns usize))
  (align8 (wrap+ (static_elf_data_start
                  (native_data_max_alignment symbols count))
                 (native_data_size symbols count))))

(defun static_elf_section_offset (symbols count)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize count) (returns usize))
  (let ((symbol_end
         (wrap+ (static_elf_symbol_offset symbols count)
                (wrap* (wrap+ count 3) 24))))
    (align8 (wrap+ symbol_end
                   (wrap+ (native_data_name_bytes symbols count) 66)))))

(defun emit_static_elf_headers (buffer symbols count)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_symbol) symbols)
           (type usize count) (returns c-int))
  (let ((alignment (native_data_max_alignment symbols count))
        (data_start (static_elf_data_start
                     (native_data_max_alignment symbols count)))
        (data_size (native_data_size symbols count))
        (symbol_offset (static_elf_symbol_offset symbols count)))
    (let ((symbol_size (wrap* (wrap+ count 3) 24)))
      (let ((name_offset (wrap+ symbol_offset symbol_size)))
        (let ((section_names
               (wrap+ name_offset (native_data_name_bytes symbols count))))
          (emit_zero_until buffer (wrap+ (deref (field-pointer buffer 'length)) 64))
          (emit_section_header buffer 1 1 6 64 0 0 0 16 0)
          (emit_section_header buffer 7 1 3
                               (wrap-cast u64 data_start)
                               (wrap-cast u64 data_size) 0 0
                               (wrap-cast u64 alignment) 0)
          (emit_section_header buffer 13 4 0
                               (wrap-cast u64 symbol_offset) 0 4 1 8 24)
          (emit_section_header buffer 24 2 0
                               (wrap-cast u64 symbol_offset)
                               (wrap-cast u64 symbol_size) 5
                               (wrap-cast u64
                                (wrap+ 3 (native_data_selected_count_from
                                          symbols 0 count 0))) 8 24)
          (emit_section_header buffer 32 3 0
                               (wrap-cast u64 name_offset)
                               (wrap-cast u64
                                (native_data_name_bytes symbols count))
                               0 0 1 0)
          (emit_section_header buffer 40 3 0
                               (wrap-cast u64 section_names) 66 0 0 1 0)
          (emit_section_header buffer 50 1 0
                               (wrap-cast u64 (wrap+ section_names 66))
                               0 0 0 1 0))))))

(defun emit_static_elf_object (machine flags symbols count buffer)
  (declare (type u16 machine) (type u32 flags)
           (type (ptr native_data_symbol) symbols)
           (type usize count) (type (ptr byte_buffer) buffer) (returns c-int))
  (let ((section_offset (static_elf_section_offset symbols count)))
    (emit_elf_header buffer section_offset machine flags)
    (emit_zero_until buffer
                     (static_elf_data_start
                      (native_data_max_alignment symbols count)))
    (emit_native_data_from buffer symbols 0 count)
    (emit_zero_until buffer (static_elf_symbol_offset symbols count))
    (emit_static_elf_symbols buffer symbols count)
    (emit_static_data_names buffer symbols count)
    (emit_section_names buffer)
    (emit_zero_until buffer section_offset)
    (emit_static_elf_headers buffer symbols count)))

(defun write_elf64_data (machine flags symbols count buffer)
  (declare (type u16 machine) (type u32 flags)
           (type (ptr native_data_symbol) symbols)
           (type usize count) (type (ptr byte_buffer) buffer)
           (returns c-int) (c-export :c))
  (if (< 16777215 count) 0
      (if (< 0 (deref (field-pointer buffer 'length))) 0
          (if (= (valid_data_symbols_p symbols count) 0) 0
              (let ((data_size (native_data_size symbols count)))
                (if (< (deref (field-pointer buffer 'capacity)) data_size) 0
                    (let ((section (static_elf_section_offset symbols count)))
                      (let ((size (wrap+ section 512)))
                        (if (< section data_size) 0
                            (if (< size section) 0
                                (if (< (deref (field-pointer buffer 'capacity)) size) 0
                                    (emit_static_elf_object
                                     machine flags symbols count buffer))))))))))))

;; COFF data-only output uses one section and the same data layout as ELF.
(defun static_coff_long_name_bytes_from (symbols index count)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize index count) (returns usize))
  (if (= index count) 0
      (let ((length (deref (field-pointer
                            (native_data_at symbols index) 'name_length))))
        (wrap+ (if (< 8 length) (wrap+ length 1) (wrap-cast usize 0))
               (static_coff_long_name_bytes_from symbols (wrap+ index 1) count)))))

(defun static_coff_data_start (alignment)
  (declare (type usize alignment) (returns usize))
  (native_align_up 60 alignment))

(defun static_coff_alignment_flag (alignment)
  (declare (type usize alignment) (returns u32))
  (cond
    ((= alignment 1) #x00100000)
    ((= alignment 2) #x00200000)
    ((= alignment 4) #x00300000)
    ((= alignment 8) #x00400000)
    ((= alignment 16) #x00500000)
    ((= alignment 32) #x00600000)
    ((= alignment 64) #x00700000)
    ((= alignment 128) #x00800000)
    ((= alignment 256) #x00900000)
    ((= alignment 512) #x00a00000)
    ((= alignment 1024) #x00b00000)
    ((= alignment 2048) #x00c00000)
    (t #x00d00000)))

(defun static_coff_symbol_offset (symbols count)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize count) (returns usize))
  (native_align_up
   (wrap+ (static_coff_data_start (native_data_max_alignment symbols count))
          (native_data_size symbols count)) 4))

(defun emit_static_coff_header (buffer symbols count)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_symbol) symbols)
           (type usize count) (returns c-int))
  (let ((data_start
         (static_coff_data_start (native_data_max_alignment symbols count))))
    (emit_integer buffer #x8664 2)
    (emit_integer buffer 1 2)
    (emit_integer buffer 0 4)
    (emit_integer buffer (wrap-cast u64
                                    (static_coff_symbol_offset symbols count)) 4)
    (emit_integer buffer (wrap-cast u64 (wrap+ count 1)) 4)
    (emit_integer buffer 0 4)
    (emit_integer buffer #x617461642e 8)
    (emit_integer buffer 0 8)
    (emit_integer buffer (wrap-cast u64 (native_data_size symbols count)) 4)
    (emit_integer buffer (wrap-cast u64 data_start) 4)
    (emit_integer buffer 0 8)
    (emit_integer buffer 0 4)
    (emit_integer buffer 0 4)
    (emit_integer buffer
                  (wrap-cast
                   u64
                   (wrap+ #xc0000040
                          (static_coff_alignment_flag
                           (native_data_max_alignment symbols count)))) 4)))

(defun emit_static_coff_name (buffer symbol long_offset)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_symbol) symbol)
           (type usize long_offset) (returns c-int))
  (let ((length (deref (field-pointer symbol 'name_length))))
    (if (< 8 length)
        (progn (emit_integer buffer 0 4)
               (emit_integer buffer (wrap-cast u64 long_offset) 4))
        (progn
          (emit_source_bytes buffer (deref (field-pointer symbol 'name)) length)
          (emit_zero_until buffer (wrap+ (deref (field-pointer buffer 'length))
                                        (wrap- 8 length)))))))

(defun emit_static_coff_symbols_from (buffer symbols index count long_offset)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_symbol) symbols)
           (type usize index count long_offset) (returns usize))
  (if (= index count) long_offset
      (let ((symbol (native_data_at symbols index)))
        (emit_static_coff_name buffer symbol long_offset)
        (emit_integer buffer (wrap-cast u64 (native_data_offset symbols index)) 4)
        (emit_integer buffer 1 2)
        (emit_integer buffer 0 2)
        (emit_integer buffer
                      (if (= (deref (field-pointer symbol 'exported)) 1) 2 3) 1)
        (emit_integer buffer 0 1)
        (emit_static_coff_symbols_from
         buffer symbols (wrap+ index 1) count
         (if (< 8 (deref (field-pointer symbol 'name_length)))
             (wrap+ long_offset
                    (wrap+ (deref (field-pointer symbol 'name_length)) 1))
             long_offset)))))

(defun emit_static_coff_long_names_from (buffer symbols index count)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_symbol) symbols)
           (type usize index count) (returns c-int))
  (if (= index count) 1
      (let ((symbol (native_data_at symbols index)))
        (if (< 8 (deref (field-pointer symbol 'name_length)))
            (progn
              (emit_source_bytes buffer (deref (field-pointer symbol 'name))
                                 (deref (field-pointer symbol 'name_length)))
              (emit_byte_unchecked buffer 0)
              (emit_static_coff_long_names_from buffer symbols
                                                (wrap+ index 1) count))
            (emit_static_coff_long_names_from buffer symbols
                                              (wrap+ index 1) count)))))

(defun emit_static_coff_symbols (buffer symbols count)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_data_symbol) symbols)
           (type usize count) (returns c-int))
  (emit_integer buffer #x617461642e 8)
  (emit_integer buffer 0 4)
  (emit_integer buffer 1 2)
  (emit_integer buffer 0 2)
  (emit_integer buffer 3 1)
  (emit_integer buffer 0 1)
  (emit_static_coff_symbols_from buffer symbols 0 count 4)
  (emit_integer buffer
                (wrap-cast u64
                           (wrap+ 4 (static_coff_long_name_bytes_from
                                     symbols 0 count))) 4)
  (emit_static_coff_long_names_from buffer symbols 0 count))

(defun emit_static_coff_object (symbols count buffer)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize count) (type (ptr byte_buffer) buffer) (returns c-int))
  (emit_static_coff_header buffer symbols count)
  (emit_zero_until buffer
                   (static_coff_data_start
                    (native_data_max_alignment symbols count)))
  (emit_native_data_from buffer symbols 0 count)
  (emit_zero_until buffer (static_coff_symbol_offset symbols count))
  (emit_static_coff_symbols buffer symbols count))

(defun static_coff_object_size (symbols count)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize count) (returns usize))
  (wrap+ (static_coff_symbol_offset symbols count)
         (wrap+ (wrap* (wrap+ count 1) 18)
                (wrap+ 4 (static_coff_long_name_bytes_from symbols 0 count)))))

(defun write_coff64_data (symbols count buffer)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize count) (type (ptr byte_buffer) buffer)
           (returns c-int) (c-export :c))
  (if (< 16777215 count) 0
      (if (< 0 (deref (field-pointer buffer 'length))) 0
          (if (= (valid_data_symbols_p symbols count) 0) 0
              (let ((data_size (native_data_size symbols count)))
                (if (< (deref (field-pointer buffer 'capacity)) data_size) 0
                    (let ((size (static_coff_object_size symbols count)))
                      (if (< size data_size) 0
                          (if (< #xffffffff size) 0
                              (if (< (deref (field-pointer buffer 'capacity)) size) 0
                                  (emit_static_coff_object
                                   symbols count buffer)))))))))))
