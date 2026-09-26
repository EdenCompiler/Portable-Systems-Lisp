(include "elf64.lisp")
(include "../backend/common.lisp")

(defun valid_function_spans_from (functions index count expected code_size)
  (declare (type (ptr native_function) functions)
           (type usize index count expected code_size)
           (returns c-int))
  (if (= index count)
      (if (= expected code_size) 1 0)
      (let ((entry (native_function_at functions index)))
        (let ((offset (deref (field-pointer entry 'offset)))
              (size (deref (field-pointer entry 'size))))
          (if (= offset expected)
              (if (< 0 size)
                  (if (< code_size offset)
                      0
                      (if (< (wrap- code_size offset) size)
                          0
                          (valid_function_spans_from
                           functions (wrap+ index 1) count
                           (wrap+ offset size) code_size)))
                  0)
              0)))))

(defun valid_function_spans_p (functions count code_size)
  (declare (type (ptr native_function) functions)
           (type usize count code_size)
           (returns c-int))
  (valid_function_spans_from functions 0 count 0 code_size))

(defun multi_name_bytes_from (functions index count)
  (declare (type (ptr native_function) functions)
           (type usize index count)
           (returns usize))
  (if (= index count)
      0
      (let ((entry (native_function_at functions index)))
        (wrap+ (wrap+ (deref (field-pointer entry 'name_length)) 1)
               (multi_name_bytes_from functions (wrap+ index 1) count)))))

(defun multi_name_bytes (functions count)
  (declare (type (ptr native_function) functions)
           (type usize count)
           (returns usize))
  (wrap+ 1 (multi_name_bytes_from functions 0 count)))

(defun same_name_bytes_p (left right remaining)
  (declare (type (ptr u8) left right)
           (type usize remaining)
           (returns c-int))
  (if (= remaining 0)
      1
      (if (= (deref left) (deref right))
          (same_name_bytes_p (pointer+ left 1) (pointer+ right 1)
                             (wrap- remaining 1))
          0)))

(defun same_function_name_p (left right)
  (declare (type (ptr native_function) left right)
           (returns c-int))
  (let ((length (deref (field-pointer left 'name_length))))
    (if (= length (deref (field-pointer right 'name_length)))
        (same_name_bytes_p (deref (field-pointer left 'name))
                           (deref (field-pointer right 'name)) length)
        0)))

(defun earlier_name_p (functions candidate index)
  (declare (type (ptr native_function) functions candidate)
           (type usize index)
           (returns c-int))
  (if (= index 0)
      0
      (if (= (same_function_name_p
              (native_function_at functions (wrap- index 1)) candidate) 1)
          1
          (earlier_name_p functions candidate (wrap- index 1)))))

(defun valid_function_names_from (functions index count)
  (declare (type (ptr native_function) functions)
           (type usize index count)
           (returns c-int))
  (if (= index count)
      1
      (let ((entry (native_function_at functions index)))
        (let ((size (deref (field-pointer entry 'name_length))))
          (if (= size 0)
              0
              (if (< 1 (deref (field-pointer entry 'exported)))
                  0
                  (if (< 255 size)
                      0
                      (if (= (name_ascii_p
                              (deref (field-pointer entry 'name))
                              0 size) 0)
                          0
                          (if (= (earlier_name_p functions entry index) 1)
                              0
                              (valid_function_names_from
                               functions (wrap+ index 1)
                               count))))))))))

(defun valid_function_names_p (functions count)
  (declare (type (ptr native_function) functions)
           (type usize count)
           (returns c-int))
  (valid_function_names_from functions 0 count))

(defun local_function_count_from (functions index count)
  (declare (type (ptr native_function) functions)
           (type usize index count)
           (returns usize))
  (if (= index count)
      0
      (let ((entry (native_function_at functions index)))
        (wrap+ (if (= (deref (field-pointer entry 'exported)) 0) 1 0)
               (local_function_count_from functions (wrap+ index 1)
                                          count)))))

(defun emit_selected_symbols_from (buffer functions index count name_offset
                                   selected)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_function) functions)
           (type usize index count name_offset selected)
           (returns usize))
  (if (= index count)
      name_offset
      (let ((entry (native_function_at functions index)))
        (if (= (deref (field-pointer entry 'exported)) selected)
            (progn
              (emit_symbol buffer (wrap-cast u64 name_offset)
                           (if (= selected 0) 2 18) 1
                           (wrap-cast u64
                                      (deref (field-pointer entry 'offset)))
                           (wrap-cast u64
                                      (deref (field-pointer entry 'size))))
              (emit_selected_symbols_from
               buffer functions (wrap+ index 1) count
               (wrap+ name_offset
                      (wrap+ (deref (field-pointer entry 'name_length)) 1))
               selected))
            (emit_selected_symbols_from buffer functions (wrap+ index 1)
                                        count name_offset selected)))))

(defun emit_multi_symbols (buffer functions count)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_function) functions)
           (type usize count)
           (returns c-int))
  (emit_symbol buffer 0 0 0 0 0)
  (emit_symbol buffer 0 3 1 0 0)
  (emit_symbol buffer 0 3 2 0 0)
  (let ((next (emit_selected_symbols_from buffer functions 0 count 1 0)))
    (emit_selected_symbols_from buffer functions 0 count next 1))
  1)

(defun emit_selected_names_from (buffer functions index count selected)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_function) functions)
           (type usize index count selected)
           (returns c-int))
  (if (= index count)
      1
      (let ((entry (native_function_at functions index)))
        (if (= (deref (field-pointer entry 'exported)) selected)
            (progn
              (emit_source_bytes buffer
                                 (deref (field-pointer entry 'name))
                                 (deref (field-pointer entry 'name_length)))
              (emit_byte_unchecked buffer 0)
              (emit_selected_names_from buffer functions
                                        (wrap+ index 1) count selected))
            (emit_selected_names_from buffer functions
                                      (wrap+ index 1) count selected)))))

(defun emit_multi_names (buffer functions count)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_function) functions)
           (type usize count)
           (returns c-int))
  (emit_byte_unchecked buffer 0)
  (emit_selected_names_from buffer functions 0 count 0)
  (emit_selected_names_from buffer functions 0 count 1))

(defun multi_section_offset (code_size count name_bytes)
  (declare (type usize code_size count name_bytes)
           (returns usize))
  (let ((symbols (wrap* (wrap+ count 3) 24)))
    (align8 (wrap+ (wrap+ (align8 (wrap+ 64 code_size)) symbols)
                   (wrap+ name_bytes 66)))))

(defun emit_multi_section_headers (buffer code_size functions count
                                   name_bytes)
  (declare (type (ptr byte_buffer) buffer)
           (type (ptr native_function) functions)
           (type usize code_size count name_bytes)
           (returns c-int))
  (let ((data_offset (wrap+ 64 code_size))
        (symbol_offset (align8 (wrap+ 64 code_size)))
        (symbol_bytes (wrap* (wrap+ count 3) 24)))
    (let ((name_offset (wrap+ symbol_offset symbol_bytes)))
      (let ((section_names (wrap+ name_offset name_bytes)))
        (emit_zero_until buffer (wrap+ (deref (field-pointer buffer 'length))
                                      64))
        (emit_section_header buffer 1 1 6 64
                             (wrap-cast u64 code_size) 0 0 16 0)
        (emit_section_header buffer 7 1 3
                             (wrap-cast u64 data_offset) 0 0 0 1 0)
        (emit_section_header buffer 13 4 0
                             (wrap-cast u64 symbol_offset) 0 4 1 8 24)
        (emit_section_header buffer 24 2 0
                             (wrap-cast u64 symbol_offset)
                             (wrap-cast u64 symbol_bytes) 5
                             (wrap-cast u64
                                        (wrap+ 3
                                               (local_function_count_from
                                                functions 0 count))) 8 24)
        (emit_section_header buffer 32 3 0
                             (wrap-cast u64 name_offset)
                             (wrap-cast u64 name_bytes) 0 0 1 0)
        (emit_section_header buffer 40 3 0
                             (wrap-cast u64 section_names) 66 0 0 1 0)
        (emit_section_header buffer 50 1 0
                             (wrap-cast u64 (wrap+ section_names 66))
                             0 0 0 1 0)
        1))))

(defun emit_multi_object (machine flags code code_size functions count
                          name_bytes buffer)
  (declare (type u16 machine)
           (type u32 flags)
           (type (ptr u8) code)
           (type usize code_size count name_bytes)
           (type (ptr native_function) functions)
           (type (ptr byte_buffer) buffer)
           (returns c-int))
  (emit_elf_header buffer
                   (multi_section_offset code_size count name_bytes)
                   machine flags)
  (emit_source_bytes buffer code code_size)
  (emit_zero_until buffer (align8 (deref (field-pointer buffer 'length))))
  (emit_multi_symbols buffer functions count)
  (emit_multi_names buffer functions count)
  (emit_section_names buffer)
  (emit_zero_until buffer (align8 (deref (field-pointer buffer 'length))))
  (emit_multi_section_headers buffer code_size functions count name_bytes))

(defun write_elf64_functions (machine flags code code_size functions count
                              buffer)
  (declare (type u16 machine)
           (type u32 flags)
           (type (ptr u8) code)
           (type usize code_size count)
           (type (ptr native_function) functions)
           (type (ptr byte_buffer) buffer)
           (returns c-int)
           (c-export :c))
  (if (= count 0)
      0
      ;; Keep symbol indices and the worst-case ASCII name table in u32.
      (if (< 16777215 count)
          0
          (if (< 1048576 code_size)
              0
              (if (= (deref (field-pointer buffer 'length)) 0)
                  (if (= (valid_function_names_p functions count) 1)
                      (if (= (valid_function_spans_p
                              functions count code_size) 1)
                          (let ((name_bytes
                                 (multi_name_bytes functions count)))
                            (if (= (room_for
                                    buffer
                                    (wrap+ (multi_section_offset
                                            code_size count name_bytes)
                                           512)) 1)
                                (emit_multi_object machine flags code
                                                   code_size functions count
                                                   name_bytes buffer)
                                0))
                          0)
                      0)
                  0)))))
