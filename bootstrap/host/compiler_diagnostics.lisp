(include "compiler_imports.lisp")

(defun compiler_path_error (kind path)
  (declare (type u32 kind) (type (ptr u8) path) (returns c-int))
  (ffi:call native_host_report_error kind path 0 0)
  2)

(defun compiler_node_position (driver reference)
  (declare (type (ptr native_driver) driver) (type usize reference) (returns usize))
  (let ((nodes (deref (field-pointer (field-pointer driver 'parser) 'nodes))))
    (let ((node (pointer+ nodes (wrap-cast isize (wrap- reference 1)))))
      (deref (field-pointer node 'start)))))

(defun compiler_report_form (driver result kind)
  (declare (type (ptr native_driver) driver) (type (ptr native_unit_result) result)
           (type u32 kind) (returns c-int))
  (ffi:call native_host_report_error kind (ptr-from-address (ptr u8) 0) 0
            (compiler_node_position driver (deref (field-pointer result 'form))))
  1)

(defun compiler_report_predeclaration (driver result)
  (declare (type (ptr native_driver) driver) (type (ptr native_unit_result) result)
           (returns c-int))
  (let ((signatures (deref (field-pointer (field-pointer driver 'storage) 'signatures))))
    (let ((signature (pointer+ signatures
                       (wrap-cast isize (deref (field-pointer result 'index))))))
      (ffi:call native_host_report_error 9 (ptr-from-address (ptr u8) 0) 0
        (compiler_node_position driver (deref (field-pointer signature 'name))))
      1)))

(defun compiler_report_body (driver result)
  (declare (type (ptr native_driver) driver) (type (ptr native_unit_result) result)
           (returns c-int))
  (let ((functions (deref (field-pointer (field-pointer driver 'storage) 'functions))))
    (let ((function (pointer+ functions
                      (wrap-cast isize (deref (field-pointer result 'index))))))
      (ffi:call native_host_report_error 10
                (deref (field-pointer function 'name))
                (deref (field-pointer function 'name_length)) 0)
      1)))

(defun compiler_report_unit_error (driver result)
  (declare (type (ptr native_driver) driver) (type (ptr native_unit_result) result)
           (returns c-int))
  (let ((phase (deref (field-pointer result 'phase))))
    (cond
      ((= phase 1) (compiler_report_form driver result 6))
      ((= phase 2) (compiler_report_form driver result 7))
      ((= phase 3) (compiler_report_form driver result 8))
      ((= phase 5) (compiler_report_predeclaration driver result))
      ((= phase 6) (compiler_report_body driver result))
      (t 1))))
