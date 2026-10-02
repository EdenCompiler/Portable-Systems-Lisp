(include "read_symbols.lisp")

(defun native_ct_word_symbol (env package first last length)
  (declare (type (ptr native_ct_environment) env) (type usize package length)
           (type u64 first last) (returns usize))
  (if (= (native_ct_names_room_p env length) 0) (native_ct_fail env 1)
      (let ((start (deref (field-pointer env 'name_count))))
        (store (field-pointer env 'read_cursor) 0)
        (while (< (deref (field-pointer env 'read_cursor)) length)
          (let ((index (deref (field-pointer env 'read_cursor))))
            (store (pointer+ (deref (field-pointer env 'names))
                             (wrap-cast isize (wrap+ start index)))
                   (native_ct_upper (native_ct_seed_word_byte first last 0 0 0 index)))
            (store (field-pointer env 'read_cursor) (wrap+ index 1))))
        (native_ct_find_symbol env package
           (pointer+ (deref (field-pointer env 'names)) (wrap-cast isize start)) length))))

(defun native_ct_builtin_symbol (env first last length)
  (declare (type (ptr native_ct_environment) env) (type u64 first last)
           (type usize length) (returns usize))
  (cond
    ((= (bits-and first #xffffffff) #x3a696666)
     (native_ct_word_symbol env 3
       (wrap+ (shr64 first 32) (wrap* (bits-and last #xffffffff) #x100000000))
       (shr64 last 32) (wrap- length 4)))
    ((= (wrap-cast u8 first) 58)
     (native_ct_word_symbol env 4
       (wrap+ (shr64 first 8) (wrap* (bits-and last 255) #x100000000000000))
       (shr64 last 8) (wrap- length 1)))
    (t (native_ct_word_symbol env 5 first last length))))
