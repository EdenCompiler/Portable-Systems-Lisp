(include "source_environment.lisp")

(defun source_release_frame (frame)
  (declare (type (ptr native_source_frame) frame) (returns c-int))
  (ffi:call free
    (ptr-cast (ptr void) (deref (field-pointer (field-pointer frame 'parser) 'nodes))))
  (ffi:call free
    (ptr-cast (ptr void) (deref (field-pointer (field-pointer frame 'reader) 'identities))))
  (ffi:call free (ptr-cast (ptr void) (deref (field-pointer frame 'bytes))))
  (ffi:call free (ptr-cast (ptr void) frame))
  1)

(defun source_initialize_parser (unit frame nodes capacity)
  (declare (type (ptr native_source_unit) unit)
           (type (ptr native_source_frame) frame) (type (ptr psl_ast_node) nodes)
           (type usize capacity) (returns c-int))
  (let ((scanner (field-pointer frame 'scanner))
        (parser (field-pointer frame 'parser)))
    (store (field-pointer scanner 'data) (deref (field-pointer frame 'bytes)))
    (store (field-pointer scanner 'length) (deref (field-pointer frame 'length)))
    (store (field-pointer parser 'scanner) scanner)
    (store (field-pointer parser 'token) (field-pointer frame 'token))
    (store (field-pointer parser 'nodes) nodes)
    (store (field-pointer parser 'capacity) capacity)
    (let ((reader (field-pointer frame 'reader)))
      (store (field-pointer reader 'environment) (field-pointer unit 'environment))
      (store (field-pointer reader 'capacity) capacity)
      (store (field-pointer reader 'identities)
             (ptr-cast (ptr native_source_identity)
                       (ffi:call calloc capacity (sizeof 'native_source_identity))))
      (store (field-pointer parser 'environment) reader)
      (if (= (ptr-address (deref (field-pointer reader 'identities))) 0) 0
          (progn (store (field-pointer frame 'status) 1) 1)))))

(defun source_allocate_nodes (unit frame)
  (declare (type (ptr native_source_unit) unit)
           (type (ptr native_source_frame) frame) (returns c-int))
  (let ((capacity (wrap+ (deref (field-pointer frame 'length)) 1)))
    (if (= capacity 0) 0
        (let ((nodes (ptr-cast (ptr psl_ast_node)
                       (ffi:call calloc capacity (sizeof 'psl_ast_node)))))
          (if (= (ptr-address nodes) 0) 0
              (source_initialize_parser unit frame nodes capacity))))))

(defun source_prepare_frame (unit file)
  (declare (type (ptr native_source_unit) unit)
           (type (ptr native_source_file) file) (returns (ptr native_source_frame)))
  (let ((frame (ptr-cast (ptr native_source_frame)
                (ffi:call calloc 1 (sizeof 'native_source_frame)))))
    (if (= (ptr-address frame) 0) frame
        (progn
          (store (field-pointer frame 'file) file)
          (store (field-pointer frame 'bytes)
            (ffi:call native_source_read_file (deref (field-pointer file 'path))
                      (field-pointer frame 'length)))
          (if (= (ptr-address (deref (field-pointer frame 'bytes))) 0)
              (progn
                (ffi:call native_source_report_error 1 (deref (field-pointer file 'path)))
                (source_release_frame frame)
                (ptr-from-address (ptr native_source_frame) 0))
              (if (= (if (= (source_reserve_environment unit
                                  (deref (field-pointer frame 'length))) 1)
                         (source_allocate_nodes unit frame) (wrap-cast c-int 0)) 0)
                  (progn (source_release_frame frame)
                         (ptr-from-address (ptr native_source_frame) 0))
                  frame))))))
