(in-package #:psl.ffi.toolchain)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defun source-directory (source)
  (make-pathname :name nil :type nil :defaults (truename source)))

(defun resolve-c-source (name source)
  (let ((path (merge-pathnames name (source-directory source))))
    (unless (probe-file path)
      (fail "FFI:SOURCE file does not exist: ~A" name))
    (namestring (truename path))))

(defun run-tool (arguments)
  (let ((process (sb-ext:run-program "cc" arguments :search t
                                     :output *error-output*
                                     :error *error-output*)))
    (unless (zerop (sb-ext:process-exit-code process))
      (fail "C toolchain failed: cc ~{~A ~}" arguments))))

(defun temporary-directory ()
  (let ((base (string-right-trim "/"
                                 (or (sb-ext:posix-getenv "TMPDIR") "/tmp"))))
    (sb-posix:mkdtemp (format nil "~A/psl-ffi-XXXXXX" base))))

(defun temporary-path (directory name)
  (merge-pathnames name (pathname (concatenate 'string directory "/"))))

(defun remove-temporary-directory (directory names)
  (dolist (name names)
    (let ((path (temporary-path directory name)))
      (when (probe-file path) (delete-file path))))
  (sb-posix:rmdir directory))

(defun compile-c-source (source object)
  (run-tool (list "-std=c11" "-fno-pie" "-fno-stack-protector"
                  "-c" source "-o" (namestring object)))
  (with-open-file (stream object :element-type '(unsigned-byte 8))
    (let ((header (make-array 20 :element-type '(unsigned-byte 8))))
      (unless (and (= (read-sequence header stream) 20)
                   (equalp (subseq header 0 6) #(127 69 76 70 2 1))
                   (= (aref header 18) 62)
                   (= (aref header 19) 0))
        (fail "C compiler did not produce x86-64 little-endian ELF64: ~A"
              source)))))

(defun merge-objects (objects output)
  (run-tool (append (list "-r" "-o" (namestring output))
                    (mapcar #'namestring objects))))

(defun emit-with-c-sources (source output target c-sources emit-psl)
  (unless (eq (target-system target) :linux)
    (fail "FFI:SOURCE currently requires x86_64-linux-gnu"))
  (let* ((resolved (mapcar (lambda (name) (resolve-c-source name source))
                           c-sources))
         (directory (temporary-directory))
         (names (append '("psl.o" "merged.o")
                        (loop for item in resolved for index from 0
                              collect (format nil "c~D.o" index)))))
    (unwind-protect
         (let* ((psl-object (temporary-path directory "psl.o"))
                (c-objects (loop for item in resolved for index from 0
                                 collect (temporary-path
                                          directory (format nil "c~D.o" index))))
                (merged (temporary-path directory "merged.o")))
           (funcall emit-psl psl-object)
           (loop for c-source in resolved for c-object in c-objects
                 do (compile-c-source c-source c-object))
           (merge-objects (cons psl-object c-objects) merged)
           (sb-posix:rename (namestring merged) (namestring (pathname output)))
           output)
      (remove-temporary-directory directory names))))
