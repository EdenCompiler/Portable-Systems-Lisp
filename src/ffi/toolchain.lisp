(in-package #:psl.ffi.toolchain)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defun source-directory (source)
  (make-pathname :name nil :type nil :defaults (truename source)))

(defun resolve-c-source (declaration source)
  (let* ((name (car declaration))
         (*source-location* (cdr declaration))
         (path (merge-pathnames name (source-directory source))))
    (unless (probe-file path)
      (fail "FFI:SOURCE file does not exist: ~A" name))
    (namestring (truename path))))

(defun run-tool (program arguments)
  (let ((process (sb-ext:run-program program arguments :search t
                                     :output *error-output*
                                     :error *error-output*)))
    (unless (zerop (sb-ext:process-exit-code process))
      (fail "toolchain failed: ~A ~{~A ~}" program arguments))))

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
  (run-tool "cc" (list "-std=c11" "-fPIC" "-fno-stack-protector"
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
  (run-tool "cc" (append (list "-r" "-o" (namestring output))
                         (mapcar #'namestring objects))))

(defun emit-with-c-sources (source output target c-sources emit-psl)
  (let ((*source-location* (cdar c-sources)))
    (unless (eq (target-system target) :linux)
      (fail "FFI:SOURCE currently requires x86_64-linux-gnu")))
  (let* ((resolved (mapcar (lambda (declaration)
                             (resolve-c-source declaration source))
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

(defun validate-link-inputs (kind inputs)
  (dolist (input inputs)
    (unless (probe-file input)
      (fail "link input does not exist: ~A" input))
    (when (and (eq kind :static)
               (not (equalp (pathname-type input) "o")))
      (fail "static library inputs must be object files: ~A" input))))

(defun link-artifact (object output kind inputs)
  (validate-link-inputs kind inputs)
  (let ((paths (cons (namestring object) (mapcar #'namestring inputs))))
    (ecase kind
      (:executable
       (run-tool "cc" (append (list "-o" (namestring output)) paths)))
      (:shared
       (run-tool "cc" (append (list "-shared" "-o" (namestring output))
                               paths)))
      (:static
       (run-tool "ar" (append (list "rcsD" (namestring output)) paths)))))
  output)

(defun link-source-artifact (output kind target inputs compile-object)
  (unless (and (eq (target-architecture target) :x86-64)
               (eq (target-system target) :linux))
    (fail "linking currently requires x86_64-linux-gnu"))
  (let* ((directory (temporary-directory))
         (object (temporary-path directory "psl.o"))
         (destination (merge-pathnames output (truename ".")))
         (destination-directory
           (make-pathname :name nil :type nil :defaults destination))
         (staging-directory
           (sb-posix:mkdtemp
            (format nil "~A/.psl-link-XXXXXX"
                    (string-right-trim "/"
                                       (namestring destination-directory)))))
         (staged-output (temporary-path staging-directory "artifact")))
    (unwind-protect
         (progn
           (funcall compile-object object)
           (link-artifact object staged-output kind
                          (mapcar #'pathname inputs))
           (sb-posix:rename (namestring staged-output)
                            (namestring destination))
           output)
      (remove-temporary-directory directory '("psl.o"))
      (remove-temporary-directory staging-directory '("artifact")))))
