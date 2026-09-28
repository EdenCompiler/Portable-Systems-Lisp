;; Windows hosted path services resolve an existing file through its handle so
;; aliases use one source-unit identity, matching the POSIX realpath contract.
(ffi:import-function "_fullpath"
  ((absolute (ptr u8)) (path (ptr u8)) (capacity usize)) -> (ptr u8))
(ffi:import-function "CreateFileA"
  ((path (ptr u8)) (access u32) (sharing u32) (security (ptr void))
   (creation u32) (flags u32) (template (ptr void))) -> (ptr void))
(ffi:import-function "GetFinalPathNameByHandleA"
  ((file (ptr void)) (path (ptr u8)) (capacity u32) (flags u32)) -> u32)
(ffi:import-function "CloseHandle" ((file (ptr void))) -> c-int)
(ffi:import-function "malloc" ((size usize)) -> (ptr void))
(ffi:import-function "free" ((memory (ptr void))) -> void)

(defun source_windows_invalid_handle_p (file)
  (declare (type (ptr void) file) (returns c-int))
  (if (= (ptr-address file) (wrap- (wrap-cast usize 0) 1)) 1 0))

(defun source_windows_open_existing (path)
  (declare (type (ptr u8) path) (returns (ptr void)))
  (ffi:call "CreateFileA" path 0 7 (ptr-from-address (ptr void) 0)
            3 0 (ptr-from-address (ptr void) 0)))

(defun source_windows_read_final_path (file size)
  (declare (type (ptr void) file) (type u32 size) (returns (ptr u8)))
  (if (if (= size 0) t (= size 4294967295)) (ptr-from-address (ptr u8) 0)
      (let ((path (ptr-cast (ptr u8)
                    (ffi:call malloc (wrap+ (wrap-cast usize size) 1)))))
        (if (= (ptr-address path) 0) path
            (let ((written (ffi:call "GetFinalPathNameByHandleA"
                             file path (wrap+ size 1) 0)))
              (if (if (= written 0) t (< size written))
                  (progn
                    (ffi:call free (ptr-cast (ptr void) path))
                    (ptr-from-address (ptr u8) 0))
                  path))))))

(defun source_windows_canonical_existing (absolute)
  (declare (type (ptr u8) absolute) (returns (ptr u8)))
  (let ((file (source_windows_open_existing absolute)))
    (if (= (source_windows_invalid_handle_p file) 1) (ptr-from-address (ptr u8) 0)
        (let ((size (ffi:call "GetFinalPathNameByHandleA"
                      file (ptr-from-address (ptr u8) 0) 0 0)))
          (let ((path (source_windows_read_final_path file size)))
            (ffi:call "CloseHandle" file)
            path)))))

(defun native_source_canonical_path (path)
  (declare (type (ptr u8) path) (returns (ptr u8)) (c-export :c))
  (let ((absolute (ffi:call _fullpath (ptr-from-address (ptr u8) 0) path 0)))
    (if (= (ptr-address absolute) 0) absolute
        (let ((canonical (source_windows_canonical_existing absolute)))
          (ffi:call free (ptr-cast (ptr void) absolute))
          canonical))))

(defun native_source_windows_paths ()
  (declare (returns c-int) (c-export :c))
  1)
