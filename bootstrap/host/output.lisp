(include "../binary_types.lisp")

;; Host file output is a separately compiled PSL unit. The C library provides
;; the file operations; no target backend depends on it.
(ffi:import-function "calloc" ((count usize) (size usize)) -> (ptr void))
(ffi:import-function "free" ((memory (ptr void))) -> void)
(ffi:import-function "fopen" ((path (ptr u8)) (mode (ptr u8))) -> (ptr void))
(ffi:import-function "fwrite"
  ((bytes (ptr void)) (size usize) (count usize) (stream (ptr void))) -> usize)
(ffi:import-function "fclose" ((stream (ptr void))) -> c-int)

(defun output_open_binary (path)
  (declare (type (ptr u8) path) (returns (ptr void)))
  (let ((mode (ptr-cast (ptr u8) (ffi:call calloc 3 1))))
    (if (= (ptr-address mode) 0) (ptr-from-address (ptr void) 0)
        (progn
          (store mode 119) ; 'w'
          (store (pointer+ mode 1) 98) ; 'b'; calloc supplies the NUL
          (let ((stream (ffi:call fopen path mode)))
            (ffi:call free (ptr-cast (ptr void) mode))
            stream)))))

(defun output_write_and_close (stream object)
  (declare (type (ptr void) stream) (type (ptr byte_buffer) object) (returns c-int))
  (let ((written (ffi:call fwrite
                   (ptr-cast (ptr void) (deref (field-pointer object 'data)))
                   1 (deref (field-pointer object 'length)) stream)))
    (let ((closed (ffi:call fclose stream)))
      (if (= written (deref (field-pointer object 'length)))
          (if (= closed 0) 1 0) 0))))

(defun native_host_write_object (path object)
  (declare (type (ptr u8) path) (type (ptr byte_buffer) object)
           (returns c-int) (c-export :c))
  (let ((stream (output_open_binary path)))
    (if (= (ptr-address stream) 0) 0
        (output_write_and_close stream object))))
