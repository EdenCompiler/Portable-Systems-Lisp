(include "source_paths.lisp")
(include "source_c_files.lisp")
(include "source_buffers.lisp")
(include "source_frames.lisp")

(defun source_load_include_path (unit parent parser bytes root name capacity)
  (declare (type (ptr native_source_unit) unit) (type (ptr u8) parent bytes name)
           (type (ptr psl_parser) parser) (type usize root capacity) (returns c-int))
  (if (= (ffi:call native_source_include_copy parser bytes root name capacity) 0) 0
      (let ((path (source_include_path parent name)))
        (if (= (ptr-address path) 0) 0
            (let ((result (source_load_file unit path)))
              (ffi:call free (ptr-cast (ptr void) path))
              result)))))

(defun source_load_include (unit frame)
  (declare (type (ptr native_source_unit) unit)
           (type (ptr native_source_frame) frame) (returns c-int))
  (let ((parser (field-pointer frame 'parser))
        (bytes (deref (field-pointer frame 'bytes)))
        (root (deref (field-pointer frame 'root))))
    (let ((capacity (wrap+ (ffi:call native_source_include_size parser bytes root) 1)))
      (if (= capacity 0) 0
          (let ((name (ptr-cast (ptr u8) (ffi:call malloc capacity))))
            (if (= (ptr-address name) 0) 0
                (let ((result (source_load_include_path unit
                                (deref (field-pointer (deref (field-pointer frame 'file)) 'path))
                                parser bytes root name capacity)))
                  (ffi:call free (ptr-cast (ptr void) name))
                  result)))))))

(defun source_append_frame_form (unit frame)
  (declare (type (ptr native_source_unit) unit)
           (type (ptr native_source_frame) frame) (returns c-int))
  (let ((parser (field-pointer frame 'parser)))
    (let ((node (pointer+ (deref (field-pointer parser 'nodes))
                  (wrap-cast isize (wrap- (deref (field-pointer frame 'root)) 1)))))
      (source_append_form unit
        (pointer+ (deref (field-pointer frame 'bytes))
                  (wrap-cast isize (deref (field-pointer node 'start))))
        (deref (field-pointer node 'length))))))

(defun source_process_form (unit frame)
  (declare (type (ptr native_source_unit) unit)
           (type (ptr native_source_frame) frame) (returns c-int))
  (let ((kind (ffi:call native_source_form_kind (field-pointer frame 'parser)
                      (deref (field-pointer frame 'bytes))
                      (deref (field-pointer frame 'root)))))
    (cond
      ((= kind 2) (source_load_include unit frame))
      ((= kind 3) (source_record_c_path unit frame))
      ((= kind 1) (source_append_frame_form unit frame))
      (t (ffi:call native_source_report_error 3
                  (deref (field-pointer (deref (field-pointer frame 'file)) 'path)))
         0))))

(defun source_frame_pending_p (frame)
  (declare (type (ptr native_source_frame) frame) (returns c-int))
  (if (= (deref (field-pointer frame 'status)) 1)
      (if (= (deref (field-pointer frame 'root)) 0) 0 1) 0))

(defun source_load_forms (unit frame)
  (declare (type (ptr native_source_unit) unit)
           (type (ptr native_source_frame) frame) (returns c-int))
  (let ((parser (field-pointer frame 'parser)))
    (store (field-pointer frame 'root) (ffi:call parser_next parser))
    (while (= (source_frame_pending_p frame) 1)
      (store (field-pointer frame 'status) (source_process_form unit frame))
      (if (= (deref (field-pointer frame 'status)) 1)
          (store (field-pointer frame 'root) (ffi:call parser_next parser))
          (wrap-cast usize 0)))
    (if (= (deref (field-pointer parser 'error)) 0)
        (deref (field-pointer frame 'status))
        (progn
          (ffi:call native_source_report_error 4
                    (deref (field-pointer (deref (field-pointer frame 'file)) 'path)))
          0))))

(defun source_load_new_file (unit file)
  (declare (type (ptr native_source_unit) unit) (type (ptr native_source_file) file)
           (returns c-int))
  (let ((frame (source_prepare_frame file)))
    (if (= (ptr-address frame) 0) 0
        (let ((result (source_load_forms unit frame)))
          (source_release_frame frame)
          (store (field-pointer file 'active) 0)
          result))))

(defun source_check_existing_file (file)
  (declare (type (ptr native_source_file) file) (returns c-int))
  (if (= (deref (field-pointer file 'active)) 0) 1
      (progn
        (ffi:call native_source_report_error 2 (deref (field-pointer file 'path)))
        0)))

(defun source_load_canonical_file (unit canonical)
  (declare (type (ptr native_source_unit) unit) (type (ptr u8) canonical)
           (returns c-int))
  (let ((file (source_find_file unit canonical)))
    (if (= (ptr-address file) 0)
        (let ((added (source_add_file unit canonical)))
          (if (= (ptr-address added) 0)
              (progn (ffi:call free (ptr-cast (ptr void) canonical)) 0)
              (source_load_new_file unit added)))
        (progn
          (ffi:call free (ptr-cast (ptr void) canonical))
          (source_check_existing_file file)))))

(defun source_load_file (unit path)
  (declare (type (ptr native_source_unit) unit) (type (ptr u8) path) (returns c-int))
  (let ((canonical (ffi:call native_source_canonical_path path)))
    (if (= (ptr-address canonical) 0)
        (progn (ffi:call native_source_report_error 1 path) 0)
        (source_load_canonical_file unit canonical))))

(defun source_take_bytes (unit length)
  (declare (type (ptr native_source_unit) unit) (type (ptr usize) length)
           (returns (ptr u8)))
  (let ((bytes (deref (field-pointer unit 'bytes))))
    (store length (deref (field-pointer unit 'length)))
    (if (= (ptr-address bytes) 0)
        (ptr-cast (ptr u8) (ffi:call calloc 1 1))
        bytes)))

(defun native_read_source_unit (path length c_sources)
  (declare (type (ptr u8) path) (type (ptr usize) length)
           (type (ptr (ptr native_c_source_path)) c_sources)
           (returns (ptr u8)) (c-export :c))
  (let ((unit (ptr-cast (ptr native_source_unit)
               (ffi:call calloc 1 (sizeof 'native_source_unit)))))
    (if (= (ptr-address unit) 0) (ptr-from-address (ptr u8) 0)
        (let ((status (source_load_file unit path)))
          (source_release_files unit)
          (let ((bytes (if (= status 1) (source_take_bytes unit length)
                           (progn
                             (ffi:call free
                               (ptr-cast (ptr void) (deref (field-pointer unit 'bytes))))
                             (ptr-from-address (ptr u8) 0)))))
            (if (= status 1)
                (source_take_c_paths unit c_sources)
                (source_release_c_paths (field-pointer unit 'c_sources)))
            (ffi:call free (ptr-cast (ptr void) unit))
            bytes)))))
