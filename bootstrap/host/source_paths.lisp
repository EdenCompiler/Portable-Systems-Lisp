(include "source_imports.lisp")

(defun source_path_absolute_p (name windows)
  (declare (type (ptr u8) name) (type c-int windows) (returns c-int))
  (let ((first (deref name)))
    (if (= first 47) 1
        (if (= windows 0) 0
            (if (= first 92) 1
                (if (= first 0) 0
                    (if (= (deref (pointer+ name 1)) 58) 1 0)))))))

(defun source_path_separator (parent windows)
  (declare (type (ptr u8) parent) (type c-int windows) (returns (ptr u8)))
  (let ((slash (ffi:call strrchr parent 47)))
    (if (= windows 0) slash
        (let ((backslash (ffi:call strrchr parent 92)))
          (if (= (ptr-address backslash) 0) slash
              (if (< (ptr-address slash) (ptr-address backslash))
                  backslash slash))))))

(defun source_directory_size (parent windows)
  (declare (type (ptr u8) parent) (type c-int windows) (returns usize))
  (let ((separator (source_path_separator parent windows)))
    (if (= (ptr-address separator) 0) (wrap-cast usize 0)
        (wrap+ (wrap- (ptr-address separator) (ptr-address parent)) 1))))

(defun source_copy_path (parent name directory size)
  (declare (type (ptr u8) parent name) (type usize directory size)
           (returns (ptr u8)))
  (let ((total (wrap+ directory size)))
    (if (< total directory) (ptr-from-address (ptr u8) 0)
        (let ((result (ptr-cast (ptr u8) (ffi:call malloc total))))
          (if (= (ptr-address result) 0) result
              (progn
                (ffi:call memcpy (ptr-cast (ptr void) result)
                          (ptr-cast (ptr void) parent) directory)
                (ffi:call memcpy
                  (ptr-cast (ptr void) (pointer+ result (wrap-cast isize directory)))
                  (ptr-cast (ptr void) name) size)
                result))))))

(defun source_include_path (parent name)
  (declare (type (ptr u8) parent name) (returns (ptr u8)))
  (let ((windows (ffi:call native_source_windows_paths))
        (size (wrap+ (ffi:call strlen name) 1)))
    (if (= size 0) (ptr-from-address (ptr u8) 0)
        (source_copy_path parent name
          (if (= (source_path_absolute_p name windows) 1)
              (wrap-cast usize 0) (source_directory_size parent windows))
          size))))
