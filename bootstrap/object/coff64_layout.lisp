(include "function_validation.lisp")
(include "win64_unwind.lisp")

;; Four fixed sections: .text, empty .data, .pdata, and .xdata.
(defun coff_align4 (value)
  (declare (type usize value) (returns usize))
  (bits-and (wrap+ value 3) (wrap- 0 4)))

(defun coff_defined_count_from (functions index count)
  (declare (type (ptr native_function) functions) (type usize index count) (returns usize))
  (if (= index count) 0
      (wrap+ (if (= (deref (field-pointer (native_function_at functions index) 'imported)) 1)
                   (wrap-cast usize 0) (wrap-cast usize 1))
             (coff_defined_count_from functions (wrap+ index 1) count))))

(defun coff_xdata_bytes_from (functions index count)
  (declare (type (ptr native_function) functions) (type usize index count) (returns usize))
  (if (= index count) 0
      (let ((entry (native_function_at functions index)))
        (wrap+ (if (= (deref (field-pointer entry 'imported)) 1) (wrap-cast usize 0)
                   (win64_unwind_bytes (deref (field-pointer entry 'frame_size))))
               (coff_xdata_bytes_from functions (wrap+ index 1) count)))))

(defun coff_emitted_count_from (functions index count)
  (declare (type (ptr native_function) functions) (type usize index count) (returns usize))
  (if (= index count) 0
      (wrap+ (native_function_emitted_p (native_function_at functions index))
             (coff_emitted_count_from functions (wrap+ index 1) count))))

(defun coff_long_names_from (functions index count)
  (declare (type (ptr native_function) functions) (type usize index count) (returns usize))
  (if (= index count) 0
      (let ((entry (native_function_at functions index)))
        (wrap+ (if (= (native_function_emitted_p entry) 1)
                   (if (< 8 (deref (field-pointer entry 'name_length)))
                       (wrap+ (deref (field-pointer entry 'name_length)) 1) (wrap-cast usize 0))
                   (wrap-cast usize 0))
               (coff_long_names_from functions (wrap+ index 1) count)))))

(defun coff_relocation_records (count)
  (declare (type usize count) (returns usize))
  (if (< 65535 count) (wrap+ count 1) count))

(defun coff_pdata_offset (code_size)
  (declare (type usize code_size) (returns usize))
  (coff_align4 (wrap+ 180 code_size)))

(defun coff_xdata_offset (code_size definitions)
  (declare (type usize code_size definitions) (returns usize))
  (coff_align4 (wrap+ (coff_pdata_offset code_size) (wrap* 12 definitions))))

(defun coff_text_relocation_offset (code_size definitions xdata_size)
  (declare (type usize code_size definitions xdata_size) (returns usize))
  (coff_align4 (wrap+ (coff_xdata_offset code_size definitions) xdata_size)))

(defun coff_pdata_relocation_offset (code_size definitions xdata_size calls)
  (declare (type usize code_size definitions xdata_size calls) (returns usize))
  (coff_align4 (wrap+ (coff_text_relocation_offset code_size definitions xdata_size)
                     (wrap* 10 (coff_relocation_records calls)))))

(defun coff_symbol_offset (code_size definitions xdata_size calls)
  (declare (type usize code_size definitions xdata_size calls) (returns usize))
  (coff_align4 (wrap+ (coff_pdata_relocation_offset code_size definitions xdata_size calls)
                     (wrap* 10 (coff_relocation_records (wrap* 3 definitions))))))

(defun coff_object_bytes (code_size definitions xdata_size calls symbols names)
  (declare (type usize code_size definitions xdata_size calls symbols names) (returns usize))
  (wrap+ (coff_symbol_offset code_size definitions xdata_size calls)
         (wrap+ (wrap* 18 (wrap+ 4 symbols)) (wrap+ 4 names))))
