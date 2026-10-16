;; Diagnostic wording and selection belong to the PSL host. The small C
;; adapter only exposes the platform's stderr macro and integer formatting.

(ffi:import-function "native_host_stderr" () -> (ptr void))
(ffi:import-function "native_host_stdout" () -> (ptr void))
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

(defun diagnostic_cli_usage (stream)
  (declare (type (ptr void) stream) (returns void))
  (diagnostic_write_line stream (ffi:c-string "Usage: pslcc-native [-c|--emit=exe|static|shared] SOURCE.lisp -o OUTPUT [--link-input=FILE]... [--target=TARGET] [--profile=hosted|freestanding] [-O0|-O1] [--dump-ir=hir|ssa|lir|all]"))
  (diagnostic_write_line stream (ffi:c-string "Targets: x86_64-linux-gnu, aarch64-linux-gnu, riscv64-linux-gnu, x86_64-windows-gnu"))
  (diagnostic_write_line stream (ffi:c-string "Profiles: hosted, freestanding")))

(defun diagnostic_cli_error (kind text)
  (declare (type u32 kind) (type (ptr u8) text) (returns void))
  (let ((stream (ffi:call native_host_stderr)))
    (cond
      ((= kind 1) (diagnostic_write_path stream (ffi:c-string "unknown option ") text))
      ((= kind 2)
       (diagnostic_write_c_string stream text)
       (diagnostic_write_line stream (ffi:c-string " requires a value")))
      ((= kind 3) (diagnostic_write_path stream (ffi:c-string "unexpected argument ") text))
      ((= kind 4) (diagnostic_write_line stream (ffi:c-string "SOURCE and -o OUTPUT are required")))
      ((= kind 5) (diagnostic_write_line stream (ffi:c-string "-c cannot be combined with --emit")))
      ((= kind 6) (diagnostic_write_line stream (ffi:c-string "-c does not accept link inputs")))
      ((= kind 7)
       (diagnostic_write_c_string stream (ffi:c-string "unknown IR dump mode "))
       (diagnostic_write_line stream text))
      (t (diagnostic_noop stream)))
    (diagnostic_cli_usage stream)))

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
       (diagnostic_write_path stream (ffi:c-string "cannot write or link output: ") text))
      ((= kind 5)
       (diagnostic_write_line
        stream
        (ffi:c-string
         "usage: pslcc-native-slice SOURCE.lisp -o OUTPUT [--emit=exe|static|shared] [--link-input=FILE]... [-O0|-O1] [--target=TARGET] [--profile=freestanding|hosted]"))
       (diagnostic_write_line stream
         (ffi:c-string "object output: pslcc-native-slice -c SOURCE.lisp -o OUTPUT.o or [OPTIONS] SOURCE.lisp OUTPUT.o")))
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
      ((= kind 12)
       (diagnostic_write_line stream (ffi:c-string "cannot register hosted runtime: reserved symbol or insufficient storage")))
      ((= kind 19) (diagnostic_cli_usage (ffi:call native_host_stdout)))
      ((= kind 20) (diagnostic_cli_error (wrap-cast u32 length) text))
      ((= kind 21)
       (diagnostic_write_line stream (ffi:c-string "cannot write native IR dump")))
      ((= kind 22)
       (diagnostic_write_line stream (ffi:c-string "cannot allocate native IR dump buffer")))
      ((= kind 23)
       (diagnostic_write_line stream (ffi:c-string "cannot represent verified native IR text")))
      (t (diagnostic_noop stream)))))

(defun source_error_kind_p (kind)
  (declare (type u32 kind) (returns c-int))
  (if (< kind 1) 0 (if (< 5 kind) 0 1)))

(defun source_error_prefix (kind)
  (declare (type u32 kind) (returns (ptr u8)))
  (cond
    ((= kind 1) (ffi:c-string "cannot read source: "))
    ((= kind 2) (ffi:c-string "circular source include: "))
    ((= kind 3) (ffi:c-string "invalid include form: "))
    ((= kind 4) (ffi:c-string "reader error: "))
    ((= kind 5) (ffi:c-string "duplicate C source: "))
    (t (ffi:c-string ""))))

(defun native_source_report_error (kind path)
  (declare (type u32 kind) (type (ptr u8) path)
           (returns void) (c-export :c))
  (let ((stream (ffi:call native_host_stderr)))
    (if (= (source_error_kind_p kind) 1)
        (diagnostic_write_path stream (source_error_prefix kind) path)
        (diagnostic_noop stream))))
