;; Diagnostic wording and selection belong to the PSL host. The small C
;; adapter only exposes the platform's stderr macro and integer formatting.

(ffi:import-function "native_host_stderr" () -> (ptr void))
(ffi:import-function "native_host_write_usize"
  ((stream (ptr void)) (value usize)) -> void)
(ffi:import-function "native_host_write_c_string"
  ((stream (ptr void)) (text (ptr u8))) -> void)
(ffi:import-function "native_host_write_bytes"
  ((stream (ptr void)) (bytes (ptr u8)) (length usize)) -> void)
(ffi:import-function "native_host_write_byte"
  ((stream (ptr void)) (byte u8)) -> void)

(defun diagnostic_write_c_string (stream text)
  (declare (type (ptr void) stream) (type (ptr u8) text) (returns void))
  (ffi:call native_host_write_c_string stream text))

(defun diagnostic_write_bytes (stream text length)
  (declare (type (ptr void) stream) (type (ptr u8) text)
           (type usize length) (returns void))
  (ffi:call native_host_write_bytes stream text length))

(defun diagnostic_newline (stream)
  (declare (type (ptr void) stream) (returns void))
  (ffi:call native_host_write_byte stream 10))

(defun diagnostic_write_line (stream text)
  (declare (type (ptr void) stream) (type (ptr u8) text) (returns void))
  (diagnostic_write_c_string stream text)
  (diagnostic_newline stream))

(defun diagnostic_noop (stream)
  (declare (type (ptr void) stream) (returns void))
  (diagnostic_write_bytes stream (ffi:c-string "") 0))

(defun diagnostic_write_path (stream prefix path)
  (declare (type (ptr void) stream) (type (ptr u8) prefix path)
           (returns void))
  (diagnostic_write_c_string stream prefix)
  (diagnostic_write_c_string stream path)
  (diagnostic_newline stream))

(defun diagnostic_write_position (stream prefix position)
  (declare (type (ptr void) stream) (type (ptr u8) prefix)
           (type usize position) (returns void))
  (diagnostic_write_c_string stream prefix)
  (ffi:call native_host_write_usize stream position)
  (diagnostic_newline stream))

(defun diagnostic_write_name (stream prefix text length)
  (declare (type (ptr void) stream) (type (ptr u8) prefix text)
           (type usize length) (returns void))
  (diagnostic_write_c_string stream prefix)
  (diagnostic_write_bytes stream text length)
  (diagnostic_newline stream))

(defun native_host_report_error (kind text length position)
  (declare (type u32 kind) (type (ptr u8) text)
           (type usize length position) (returns void) (c-export :c))
  (let ((stream (ffi:call native_host_stderr)))
    (cond
      ((= kind 1)
       (diagnostic_write_path stream (ffi:c-string "cannot read source: ") text))
      ((= kind 2)
       (diagnostic_write_line stream
                              (ffi:c-string "cannot allocate compiler buffers")))
      ((= kind 3)
       (diagnostic_write_path stream
                              (ffi:c-string "unsupported or malformed source: ") text))
      ((= kind 4)
       (diagnostic_write_path stream (ffi:c-string "cannot write object: ") text))
      ((= kind 5)
       (diagnostic_write_line
        stream
        (ffi:c-string
         "usage: pslcc-native-slice [-O0|-O1] [--target=x86_64-linux-gnu|--target=aarch64-linux-gnu|--target=riscv64-linux-gnu|--target=x86_64-windows-gnu] SOURCE.lisp OUTPUT.o")))
      ((= kind 6)
       (diagnostic_write_position stream
                                  (ffi:c-string "cannot register layout at byte ")
                                  position))
      ((= kind 7)
       (diagnostic_write_position stream
                                  (ffi:c-string "cannot parse C import at byte ")
                                  position))
      ((= kind 8)
       (diagnostic_write_position stream
                                  (ffi:c-string "cannot parse declaration at byte ")
                                  position))
      ((= kind 9)
       (diagnostic_write_position stream
                                  (ffi:c-string "cannot predeclare function at byte ")
                                  position))
      ((= kind 10)
       (diagnostic_write_name stream (ffi:c-string "cannot compile function: ")
                              text length))
      ((= kind 11)
       (diagnostic_write_name
        stream (ffi:c-string "WITHOUT-ALLOCATION cannot certify call to ")
        text length))
      (t (diagnostic_noop stream)))))

(defun source_error_kind_p (kind)
  (declare (type u32 kind) (returns c-int))
  (if (< kind 1) 0 (if (< 4 kind) 0 1)))

(defun source_error_prefix (kind)
  (declare (type u32 kind) (returns (ptr u8)))
  (cond
    ((= kind 1) (ffi:c-string "cannot read source: "))
    ((= kind 2) (ffi:c-string "circular source include: "))
    ((= kind 3) (ffi:c-string "invalid include form: "))
    ((= kind 4) (ffi:c-string "reader error: "))
    (t (ffi:c-string ""))))

(defun native_source_report_error (kind path)
  (declare (type u32 kind) (type (ptr u8) path)
           (returns void) (c-export :c))
  (let ((stream (ffi:call native_host_stderr)))
    (if (= (source_error_kind_p kind) 1)
        (diagnostic_write_path stream (source_error_prefix kind) path)
        (diagnostic_noop stream))))
