(include "../binary.lisp")
(include "../backend/common.lisp")

;; Shared encoded-function shape and name checks for ELF and COFF.
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

(defun valid_function_spans_from (functions index count expected code_size)
  (declare (type (ptr native_function) functions)
           (type usize index count expected code_size)
           (returns c-int))
  (if (= index count)
      (if (= expected code_size) 1 0)
      (let ((entry (native_function_at functions index)))
        (let ((offset (deref (field-pointer entry 'offset)))
              (size (deref (field-pointer entry 'size))))
          (if (= (deref (field-pointer entry 'imported)) 1)
              (if (= size 0)
                  (if (= offset 0)
                      (valid_function_spans_from functions (wrap+ index 1) count expected code_size) 0)
                  0)
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
              0))))))

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
        (wrap+ (if (= (native_function_emitted_p entry) 1)
                   (wrap+ (deref (field-pointer entry 'name_length)) 1) (wrap-cast usize 0))
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

(defun valid_function_flags_p (function)
  (declare (type (ptr native_function) function) (returns c-int))
  (if (< 1 (deref (field-pointer function 'exported))) 0
      (if (< 1 (deref (field-pointer function 'imported))) 0
          (if (< 1 (deref (field-pointer function 'referenced))) 0 1))))

(defun valid_function_name_p (function)
  (declare (type (ptr native_function) function) (returns c-int))
  (let ((size (deref (field-pointer function 'name_length))))
    (if (= size 0) 0
        (if (< 255 size) 0
            (name_ascii_p (deref (field-pointer function 'name)) 0 size)))))

(defun valid_function_names_from (functions index count)
  (declare (type (ptr native_function) functions)
           (type usize index count) (returns c-int))
  (if (= index count) 1
      (let ((entry (native_function_at functions index)))
        (if (= (valid_function_flags_p entry) 0) 0
            (if (= (valid_function_name_p entry) 0) 0
                (if (= (earlier_name_p functions entry index) 1) 0
                    (valid_function_names_from functions (wrap+ index 1) count)))))))

(defun valid_function_names_p (functions count)
  (declare (type (ptr native_function) functions)
           (type usize count)
           (returns c-int))
  (valid_function_names_from functions 0 count))
