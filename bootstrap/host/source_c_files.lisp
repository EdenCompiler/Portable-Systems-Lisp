(defun source_c_path_matches_p (entry path)
  (declare (type (ptr native_c_source_path) entry) (type (ptr u8) path)
           (returns c-int))
  (ffi:call strcmp (deref (field-pointer entry 'path)) path))

(defun source_find_c_path (entry path)
  (declare (type (ptr native_c_source_path) entry) (type (ptr u8) path)
           (returns (ptr native_c_source_path)))
  (if (= (ptr-address entry) 0) entry
      (if (= (source_c_path_matches_p entry path) 0) entry
          (source_find_c_path
           (ptr-cast (ptr native_c_source_path)
                     (deref (field-pointer entry 'next))) path))))

(defun source_append_c_path (unit canonical)
  (declare (type (ptr native_source_unit) unit) (type (ptr u8) canonical)
           (returns c-int))
  (let ((entry (ptr-cast (ptr native_c_source_path)
                         (ffi:call calloc 1 (sizeof 'native_c_source_path)))))
    (if (= (ptr-address entry) 0) 0
        (progn
          (store (field-pointer entry 'path) canonical)
          (let ((tail (deref (field-pointer unit 'c_source_tail))))
            (if (= (ptr-address tail) 0)
                (progn (store (field-pointer unit 'c_sources) entry) 1)
                (progn
                  (store (field-pointer tail 'next) (ptr-cast (ptr void) entry))
                  1)))
          (store (field-pointer unit 'c_source_tail) entry)
          1))))

(defun source_decode_c_name (frame)
  (declare (type (ptr native_source_frame) frame) (returns (ptr u8)))
  (let ((parser (field-pointer frame 'parser))
        (bytes (deref (field-pointer frame 'bytes)))
        (root (deref (field-pointer frame 'root))))
    (let ((capacity (wrap+ (ffi:call native_source_ffi_size parser bytes root) 1)))
      (if (= capacity 0) (ptr-from-address (ptr u8) 0)
          (let ((name (ptr-cast (ptr u8) (ffi:call malloc capacity))))
            (if (= (ptr-address name) 0) name
                (if (= (ffi:call native_source_ffi_copy
                                  parser bytes root name capacity) 1) name
                    (progn
                      (ffi:call free (ptr-cast (ptr void) name))
                      (ptr-from-address (ptr u8) 0)))))))))

(defun source_resolve_c_path (frame name)
  (declare (type (ptr native_source_frame) frame) (type (ptr u8) name)
           (returns (ptr u8)))
  (let ((combined
         (source_include_path
          (deref (field-pointer (deref (field-pointer frame 'file)) 'path))
          name)))
    (if (= (ptr-address combined) 0) combined
        (let ((canonical (ffi:call native_source_canonical_path combined)))
          (if (= (ptr-address canonical) 0)
              (progn (ffi:call native_source_report_error 1 combined)
                     (wrap-cast c-int 1))
              (wrap-cast c-int 1))
          (ffi:call free (ptr-cast (ptr void) combined))
          canonical))))

(defun source_record_c_path (unit frame)
  (declare (type (ptr native_source_unit) unit)
           (type (ptr native_source_frame) frame) (returns c-int))
  (let ((name (source_decode_c_name frame)))
    (if (= (ptr-address name) 0) 0
        (let ((canonical (source_resolve_c_path frame name)))
          (ffi:call free (ptr-cast (ptr void) name))
          (if (= (ptr-address canonical) 0) 0
              (if (< 0 (ptr-address
                         (source_find_c_path
                          (deref (field-pointer unit 'c_sources)) canonical)))
                  (progn
                    (ffi:call native_source_report_error 5 canonical)
                    (ffi:call free (ptr-cast (ptr void) canonical))
                    0)
                  (if (= (source_append_c_path unit canonical) 1) 1
                      (progn
                        (ffi:call free (ptr-cast (ptr void) canonical))
                        0))))))))

(defun source_release_c_paths (root)
  (declare (type (ptr (ptr native_c_source_path)) root) (returns c-int))
  (while (< 0 (ptr-address (deref root)))
    (let ((entry (deref root)))
      (store root (ptr-cast (ptr native_c_source_path)
                            (deref (field-pointer entry 'next))))
      (ffi:call free (ptr-cast (ptr void) (deref (field-pointer entry 'path))))
      (ffi:call free (ptr-cast (ptr void) entry))))
  1)

(defun source_take_c_paths (unit output)
  (declare (type (ptr native_source_unit) unit)
           (type (ptr (ptr native_c_source_path)) output) (returns c-int))
  (store output (deref (field-pointer unit 'c_sources)))
  (store (field-pointer unit 'c_sources)
         (ptr-from-address (ptr native_c_source_path) 0))
  (store (field-pointer unit 'c_source_tail)
         (ptr-from-address (ptr native_c_source_path) 0))
  1)
