(include "source_imports.lisp")

(defun source_grow_buffer (unit needed)
  (declare (type (ptr native_source_unit) unit) (type usize needed)
           (returns c-int))
  (if (< (deref (field-pointer unit 'capacity)) needed)
      (let ((larger (ffi:call realloc
                      (ptr-cast (ptr void) (deref (field-pointer unit 'bytes))) needed)))
        (if (= (ptr-address larger) 0) 0
            (progn
              (store (field-pointer unit 'bytes) (ptr-cast (ptr u8) larger))
              (store (field-pointer unit 'capacity) needed)
              1)))
      1))

(defun source_copy_form (unit bytes size)
  (declare (type (ptr native_source_unit) unit) (type (ptr u8) bytes)
           (type usize size) (returns c-int))
  (let ((length (deref (field-pointer unit 'length))))
    (let ((output (pointer+ (deref (field-pointer unit 'bytes))
                            (wrap-cast isize length))))
      (ffi:call memcpy (ptr-cast (ptr void) output) (ptr-cast (ptr void) bytes) size)
      (store (pointer+ output (wrap-cast isize size)) 10)
      (store (pointer+ output (wrap-cast isize (wrap+ size 1))) 0)
      (store (field-pointer unit 'length) (wrap+ (wrap+ length size) 1))
      1)))

(defun source_append_form (unit bytes size)
  (declare (type (ptr native_source_unit) unit) (type (ptr u8) bytes)
           (type usize size) (returns c-int))
  (let ((length (deref (field-pointer unit 'length))))
    (let ((end (wrap+ length size)))
      (if (< end length) 0
          (let ((needed (wrap+ end 2)))
            (if (< needed end) 0
                (if (= (source_grow_buffer unit needed) 0) 0
                    (source_copy_form unit bytes size))))))))

(defun source_find_file (unit path)
  (declare (type (ptr native_source_unit) unit) (type (ptr u8) path)
           (returns (ptr native_source_file)))
  (store (field-pointer unit 'search_cursor) (deref (field-pointer unit 'files)))
  (store (field-pointer unit 'search_result) (ptr-from-address (ptr native_source_file) 0))
  (while (< 0 (ptr-address (deref (field-pointer unit 'search_cursor))))
    (let ((file (deref (field-pointer unit 'search_cursor))))
      (if (= (ffi:call strcmp (deref (field-pointer file 'path)) path) 0)
          (progn
            (store (field-pointer unit 'search_result) file)
            (store (field-pointer unit 'search_cursor)
                   (ptr-from-address (ptr native_source_file) 0)))
          (store (field-pointer unit 'search_cursor)
            (ptr-cast (ptr native_source_file) (deref (field-pointer file 'next)))))))
  (deref (field-pointer unit 'search_result)))

(defun source_add_file (unit path)
  (declare (type (ptr native_source_unit) unit) (type (ptr u8) path)
           (returns (ptr native_source_file)))
  (let ((file (ptr-cast (ptr native_source_file)
               (ffi:call calloc 1 (sizeof 'native_source_file)))))
    (if (= (ptr-address file) 0) file
        (progn
          (store (field-pointer file 'path) path)
          (store (field-pointer file 'active) 1)
          (store (field-pointer file 'next)
                 (ptr-cast (ptr void) (deref (field-pointer unit 'files))))
          (store (field-pointer unit 'files) file)
          file))))

(defun source_release_files (unit)
  (declare (type (ptr native_source_unit) unit) (returns c-int))
  (while (< 0 (ptr-address (deref (field-pointer unit 'files))))
    (let ((file (deref (field-pointer unit 'files))))
      (store (field-pointer unit 'files)
             (ptr-cast (ptr native_source_file) (deref (field-pointer file 'next))))
      (ffi:call free (ptr-cast (ptr void) (deref (field-pointer file 'path))))
      (ffi:call free (ptr-cast (ptr void) file))))
  1)
