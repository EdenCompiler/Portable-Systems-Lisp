;; Hosted source input is a separately compiled PSL unit. The C library
;; supplies byte-stream primitives; traversal and parsing stay in source_unit.
(ffi:import-function "calloc" ((count usize) (size usize)) -> (ptr void))
(ffi:import-function "realloc" ((memory (ptr void)) (size usize)) -> (ptr void))
(ffi:import-function "free" ((memory (ptr void))) -> void)
(ffi:import-function "fopen" ((path (ptr u8)) (mode (ptr u8))) -> (ptr void))
(ffi:import-function "fread"
  ((bytes (ptr void)) (size usize) (count usize) (stream (ptr void))) -> usize)
(ffi:import-function "feof" ((stream (ptr void))) -> c-int)
(ffi:import-function "ferror" ((stream (ptr void))) -> c-int)
(ffi:import-function "fclose" ((stream (ptr void))) -> c-int)

(defcstruct native_source_input
  (stream (ptr void))
  (bytes (ptr u8))
  (length usize)
  (capacity usize)
  (status c-int)
  (complete c-int))

(defun source_input_open (path)
  (declare (type (ptr u8) path) (returns (ptr void)))
  (let ((mode (ptr-cast (ptr u8) (ffi:call calloc 3 1))))
    (if (= (ptr-address mode) 0) (ptr-from-address (ptr void) 0)
        (progn
          (store mode 114) ; 'r'
          (store (pointer+ mode 1) 98) ; 'b'; calloc supplies the NUL
          (let ((stream (ffi:call fopen path mode)))
            (ffi:call free (ptr-cast (ptr void) mode))
            stream)))))

(defun source_input_grow (input)
  (declare (type (ptr native_source_input) input) (returns c-int))
  (let ((capacity (deref (field-pointer input 'capacity))))
    (let ((larger (if (= capacity 0) (wrap-cast usize 4096)
                      (wrap+ capacity capacity))))
      (if (if (= larger 0) t (< larger capacity)) 0
          (let ((bytes (ffi:call realloc
                         (ptr-cast (ptr void) (deref (field-pointer input 'bytes)))
                         larger)))
            (if (= (ptr-address bytes) 0) 0
                (progn
                  (store (field-pointer input 'bytes) (ptr-cast (ptr u8) bytes))
                  (store (field-pointer input 'capacity) larger)
                  1)))))))

(defun source_input_read_chunk (input)
  (declare (type (ptr native_source_input) input) (returns c-int))
  (let ((length (deref (field-pointer input 'length)))
        (capacity (deref (field-pointer input 'capacity))))
    (let ((available (wrap- (wrap- capacity length) 1)))
      (let ((count (ffi:call fread
                     (ptr-cast (ptr void)
                       (pointer+ (deref (field-pointer input 'bytes))
                                (wrap-cast isize length)))
                     1 available (deref (field-pointer input 'stream)))))
        (store (field-pointer input 'length) (wrap+ length count))
        (if (= count available) 1
            (if (= (ffi:call ferror (deref (field-pointer input 'stream))) 0)
                (if (= (ffi:call feof (deref (field-pointer input 'stream))) 0) 0
                    (progn (store (field-pointer input 'complete) 1) 1))
                0))))))

(defun source_input_read_all (input)
  (declare (type (ptr native_source_input) input) (returns c-int))
  (store (field-pointer input 'status) 1)
  (while (if (= (deref (field-pointer input 'status)) 1)
             (= (deref (field-pointer input 'complete)) 0) nil)
    (let ((length (deref (field-pointer input 'length)))
          (capacity (deref (field-pointer input 'capacity))))
      (if (if (= capacity 0) t (= length (wrap- capacity 1)))
          (store (field-pointer input 'status) (source_input_grow input))
          (wrap-cast c-int 0)))
    (if (= (deref (field-pointer input 'status)) 1)
        (store (field-pointer input 'status) (source_input_read_chunk input))
        (wrap-cast c-int 0)))
  (if (= (deref (field-pointer input 'status)) 1)
      (progn
        (store (pointer+ (deref (field-pointer input 'bytes))
                        (wrap-cast isize (deref (field-pointer input 'length)))) 0)
        1)
      0))

(defun source_input_finish (input length)
  (declare (type (ptr native_source_input) input) (type (ptr usize) length)
           (returns (ptr u8)))
  (ffi:call fclose (deref (field-pointer input 'stream)))
  (if (= (deref (field-pointer input 'status)) 1)
      (progn
        (store length (deref (field-pointer input 'length)))
        (deref (field-pointer input 'bytes)))
      (progn
        (ffi:call free (ptr-cast (ptr void) (deref (field-pointer input 'bytes))))
        (ptr-from-address (ptr u8) 0))))

(defun native_source_read_file (path length)
  (declare (type (ptr u8) path) (type (ptr usize) length)
           (returns (ptr u8)) (c-export :c))
  (let ((input (ptr-cast (ptr native_source_input)
                (ffi:call calloc 1 (sizeof 'native_source_input)))))
    (if (= (ptr-address input) 0) (ptr-from-address (ptr u8) 0)
        (progn
          (store (field-pointer input 'stream) (source_input_open path))
          (if (= (ptr-address (deref (field-pointer input 'stream))) 0)
              (progn
                (ffi:call free (ptr-cast (ptr void) input))
                (ptr-from-address (ptr u8) 0))
              (progn
                (source_input_read_all input)
                (let ((bytes (source_input_finish input length)))
                  (ffi:call free (ptr-cast (ptr void) input))
                  bytes)))))))
