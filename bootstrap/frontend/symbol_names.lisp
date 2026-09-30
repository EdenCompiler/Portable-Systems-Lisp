;; Canonical source function spelling is established before object writing.
;; Object API names and explicit C import strings retain their exact bytes.

(defun source_name_needs_copy_p (name length index)
  (declare (type (ptr u8) name) (type usize length index) (returns c-int))
  (if (= index length) 0
      (let ((byte (deref (pointer+ name (wrap-cast isize index)))))
        (if (= byte (source_fold_byte byte))
            (source_name_needs_copy_p name length (wrap+ index 1))
            1))))

(defun source_copy_function_name (source output length index)
  (declare (type (ptr u8) source output) (type usize length index)
           (returns c-int))
  (if (= index length) 1
      (progn
        (store (pointer+ output (wrap-cast isize index))
               (source_fold_byte (deref (pointer+ source (wrap-cast isize index)))))
        (source_copy_function_name source output length (wrap+ index 1)))))

(defun source_record_function_name (context function name length imported)
  (declare (type (ptr native_compile_context) context)
           (type (ptr native_function) function) (type (ptr u8) name)
           (type usize length) (type u8 imported) (returns c-int))
  (if (= (if (= imported 1) (wrap-cast c-int 0)
             (source_name_needs_copy_p name length 0)) 0)
      (progn (store (field-pointer function 'name) name) 1)
      (let ((used (deref (field-pointer context 'data_byte_count)))
            (capacity (deref (field-pointer context 'data_byte_capacity))))
        (if (< capacity used) 0
            (if (< (wrap- capacity used) length) 0
                (if (= (ptr-address (deref (field-pointer context 'data_bytes))) 0) 0
                    (let ((output (pointer+ (deref (field-pointer context 'data_bytes))
                                             (wrap-cast isize used))))
                      (source_copy_function_name name output length 0)
                      (store (field-pointer context 'data_byte_count) (wrap+ used length))
                      (store (field-pointer function 'name) output)
                      1)))))))
