(include "data_types.lisp")
(include "function_validation.lisp")

(defun native_data_at (symbols index)
  (declare (type (ptr native_data_symbol) symbols) (type usize index)
           (returns (ptr native_data_symbol)))
  (pointer+ symbols (wrap-cast isize index)))

(defun native_power_of_two_p (value)
  (declare (type usize value) (returns c-int))
  (if (= value 0) 0
      (if (= (bits-and value (wrap- value 1)) 0) 1 0)))

(defun native_align_up (value alignment)
  (declare (type usize value alignment) (returns usize))
  (bits-and (wrap+ value (wrap- alignment 1)) (wrap- 0 alignment)))

(defun same_data_name_p (left right)
  (declare (type (ptr native_data_symbol) left right) (returns c-int))
  (let ((length (deref (field-pointer left 'name_length))))
    (if (= length (deref (field-pointer right 'name_length)))
        (same_name_bytes_p (deref (field-pointer left 'name))
                           (deref (field-pointer right 'name)) length)
        0)))

(defun earlier_data_name_p (symbols candidate index)
  (declare (type (ptr native_data_symbol) symbols candidate)
           (type usize index) (returns c-int))
  (if (= index 0) 0
      (if (= (same_data_name_p
              (native_data_at symbols (wrap- index 1)) candidate) 1)
          1
          (earlier_data_name_p symbols candidate (wrap- index 1)))))

(defun valid_data_symbol_p (symbol)
  (declare (type (ptr native_data_symbol) symbol) (returns c-int))
  (let ((name_length (deref (field-pointer symbol 'name_length)))
        (size (deref (field-pointer symbol 'size)))
        (alignment (deref (field-pointer symbol 'alignment))))
    (if (= name_length 0) 0
        (if (< 255 name_length) 0
            (if (= (ptr-address (deref (field-pointer symbol 'name))) 0) 0
                (if (= (name_ascii_p (deref (field-pointer symbol 'name))
                                     0 name_length) 0) 0
                    (if (< 1 (deref (field-pointer symbol 'exported))) 0
                        (if (= (native_power_of_two_p alignment) 0) 0
                            (if (< 4096 alignment) 0
                                (if (= size 0) 0
                                    (if (= (ptr-address
                                            (deref (field-pointer symbol 'bytes))) 0)
                                        0 1)))))))))))

(defun valid_data_symbols_from (symbols index count)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize index count) (returns c-int))
  (if (= index count) 1
      (let ((symbol (native_data_at symbols index)))
        (if (= (valid_data_symbol_p symbol) 0) 0
            (if (= (earlier_data_name_p symbols symbol index) 1) 0
                (valid_data_symbols_from symbols (wrap+ index 1) count))))))

(defun valid_data_symbols_p (symbols count)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize count) (returns c-int))
  (if (= count 0) 0
      (if (= (ptr-address symbols) 0) 0
          (if (= (valid_data_symbols_from symbols 0 count) 0) 0
              (valid_data_layout_from symbols 0 count 0)))))

(defun valid_data_layout_from (symbols index count offset)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize index count offset) (returns c-int))
  (if (= index count) 1
      (let ((symbol (native_data_at symbols index)))
        (let ((aligned
               (native_align_up offset
                                (deref (field-pointer symbol 'alignment)))))
          (if (< aligned offset) 0
              (let ((next (wrap+ aligned
                                 (deref (field-pointer symbol 'size)))))
                (if (< next aligned) 0
                    (valid_data_layout_from symbols (wrap+ index 1)
                                            count next))))))))

(defun native_data_offset_from (symbols index stop offset)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize index stop offset) (returns usize))
  (if (= index stop) offset
      (let ((symbol (native_data_at symbols index)))
        (native_data_offset_from
         symbols (wrap+ index 1) stop
         (wrap+ (native_align_up
                 offset (deref (field-pointer symbol 'alignment)))
                (deref (field-pointer symbol 'size)))))))

(defun native_data_offset (symbols index)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize index) (returns usize))
  (let ((end (native_data_offset_from symbols 0 index 0)))
    (native_align_up
     end (deref (field-pointer (native_data_at symbols index) 'alignment)))))

(defun native_data_size (symbols count)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize count) (returns usize))
  (native_data_offset_from symbols 0 count 0))

(defun native_data_max_alignment_from (symbols index count maximum)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize index count maximum) (returns usize))
  (if (= index count) maximum
      (let ((alignment
             (deref (field-pointer (native_data_at symbols index) 'alignment))))
        (native_data_max_alignment_from
         symbols (wrap+ index 1) count
         (if (< maximum alignment) alignment maximum)))))

(defun native_data_max_alignment (symbols count)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize count) (returns usize))
  (native_data_max_alignment_from symbols 0 count 1))

(defun native_data_name_bytes_from (symbols index count)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize index count) (returns usize))
  (if (= index count) 0
      (wrap+ (wrap+ (deref (field-pointer
                            (native_data_at symbols index) 'name_length)) 1)
             (native_data_name_bytes_from symbols (wrap+ index 1) count))))

(defun native_data_name_bytes (symbols count)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize count) (returns usize))
  (wrap+ 1 (native_data_name_bytes_from symbols 0 count)))

(defun native_data_selected_count_from (symbols index count exported)
  (declare (type (ptr native_data_symbol) symbols)
           (type usize index count) (type u8 exported) (returns usize))
  (if (= index count) (wrap-cast usize 0)
      (wrap+ (if (= (deref (field-pointer
                            (native_data_at symbols index) 'exported)) exported)
                 (wrap-cast usize 1) (wrap-cast usize 0))
             (native_data_selected_count_from
              symbols (wrap+ index 1) count exported))))
