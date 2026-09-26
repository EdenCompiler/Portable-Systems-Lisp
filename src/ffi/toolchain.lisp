(in-package #:psl.ffi.toolchain)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defparameter *runtime-directory*
  (merge-pathnames "../../runtime/"
                   (make-pathname :name nil :type nil
                                  :defaults *load-truename*)))

(defparameter *runtime-dependencies*
  '((:value)
    (:platform)
    (:startup :platform)
    (:gc :startup)
    (:cons :gc)
    (:string :gc)
    (:symbol :string)
    (:package :symbol)
    (:closure :gc)
    (:values :gc)))

(defparameter *runtime-symbol-modules*
  '(("psl_rt_fixnum" . :value)
    ("psl_rt_unbox_fixnum" . :value)
    ("psl_rt_fixnum_p" . :value)
    ("psl_rt_nil_p" . :value)
    ("psl_rt_truthy" . :value)
    ("psl_rt_eq" . :value)
    ("psl_rt_cons" . :cons)
    ("psl_rt_car" . :cons)
    ("psl_rt_cdr" . :cons)
    ("psl_rt_make_string" . :string)
    ("psl_rt_string_length" . :string)
    ("psl_rt_string_byte" . :string)
    ("psl_rt_string_set_byte" . :string)
    ("psl_rt_make_symbol" . :symbol)
    ("psl_rt_symbol_name" . :symbol)
    ("psl_rt_make_package" . :package)
    ("psl_rt_package_name" . :package)
    ("psl_rt_intern" . :package)
    ("psl_rt_make_closure" . :closure)
    ("psl_rt_call_closure" . :closure)
    ("psl_rt_values2" . :values)
    ("psl_rt_nth_value" . :values)
    ("psl_rt_value_count" . :values)
    ("psl_rt_collect" . :gc)
    ("psl_rt_live_objects" . :gc)
    ("psl_rt_push_roots" . :gc)
    ("psl_rt_pop_roots" . :gc)
    ("psl_rt_kind" . :gc)))

(defun runtime-module-closure (roots)
  (let ((seen (make-hash-table)) (ordered nil))
    (labels ((visit (module)
               (unless (gethash module seen)
                 (let ((entry (assoc module *runtime-dependencies*)))
                   (unless entry (fail "unknown runtime module ~A" module))
                   (setf (gethash module seen) t)
                   (mapc #'visit (rest entry))
                   (push module ordered)))))
      (mapc #'visit (sort (copy-list roots) #'string< :key #'symbol-name)))
    (nreverse ordered)))

(defun runtime-source (module target)
  (merge-pathnames
   (if (eq module :platform)
       (ecase (target-system target)
         (:linux "platform_linux.c")
         (:windows "platform_windows.c"))
       (format nil "~(~A~).c" module))
   *runtime-directory*))

(defun target-tool (target name)
  (cond
    ((eq (target-architecture target) :riscv64)
     (concatenate 'string
                  (if (eq (target-system target) :none)
                      "riscv64-unknown-elf-" "riscv64-linux-gnu-") name))
    ((eq (target-architecture target) :aarch64)
     (concatenate 'string "aarch64-linux-gnu-" name))
    ((eq (target-system target) :none) name)
    ((eq (target-system target) :linux)
     (if (equal name "gcc") "cc" name))
    ((eq (target-system target) :windows)
     (concatenate 'string "x86_64-w64-mingw32-" name))))

(defun source-directory (source)
  (make-pathname :name nil :type nil :defaults (truename source)))

(defun resolve-c-source (declaration source)
  (let* ((name (car declaration))
         (*source-location* (cdr declaration))
         (declaring-source
           (or (and *source-location*
                    (source-location-path *source-location*))
               source))
         (path (merge-pathnames name (source-directory declaring-source))))
    (unless (probe-file path)
      (fail "FFI:SOURCE file does not exist: ~A" name))
    (namestring (truename path))))

(defun run-tool (program arguments)
  (let ((process (sb-ext:run-program program arguments :search t
                                     :output *error-output*
                                     :error *error-output*)))
    (unless (zerop (sb-ext:process-exit-code process))
      (fail "toolchain failed: ~A ~{~A ~}" program arguments))))

(defun tool-output (program arguments)
  (let ((output (make-string-output-stream)))
    (let ((process (sb-ext:run-program program arguments :search t
                                       :output output :error *error-output*)))
      (unless (zerop (sb-ext:process-exit-code process))
        (fail "toolchain failed: ~A ~{~A ~}" program arguments)))
    (get-output-stream-string output)))

(defun undefined-symbol (line)
  (let ((trimmed (string-left-trim '(#\Space #\Tab) line)))
    (when (and (> (length trimmed) 2)
               (char= (char trimmed 0) #\U)
               (char= (char trimmed 1) #\Space))
      (string-trim '(#\Space #\Tab #\Return)
                   (subseq trimmed 2)))))

(defun runtime-symbol-p (name)
  (and (<= 7 (length name))
       (string= "psl_rt_" name :end2 7)))

(defun input-runtime-modules (input target)
  (let ((output (tool-output (target-tool target "nm")
                             (list "-u" (namestring (pathname input)))))
        (modules nil))
    (with-input-from-string (stream output)
      (loop for line = (read-line stream nil nil)
            while line
            for symbol = (undefined-symbol line)
            when (and symbol (runtime-symbol-p symbol))
              do (let ((module (cdr (assoc symbol *runtime-symbol-modules*
                                           :test #'equal))))
                   (unless module
                     (fail "unknown PSL runtime dependency ~A in ~A"
                           symbol input))
                   (pushnew module modules))))
    modules))

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

(defun compile-c-source (source object target &optional runtime-p)
  (run-tool (target-tool target "gcc")
            (append (list "-std=c11" "-fno-stack-protector")
                         (when (eq (target-system target) :linux)
                           (list "-fPIC"))
                         (when (and runtime-p
                                    (eq (target-system target) :linux))
                           (list "-pthread"))
                         (list "-c" source "-o" (namestring object))))
  (with-open-file (stream object :element-type '(unsigned-byte 8))
    (let ((header (make-array 20 :element-type '(unsigned-byte 8))))
      (unless (= (read-sequence header stream) 20)
        (fail "C compiler produced a truncated object: ~A" source))
      (unless (ecase (target-object-format target)
                (:elf64
                 (and (equalp (subseq header 0 6) #(127 69 76 70 2 1))
                      (= (aref header 18)
                         (backend-contract-elf-machine
                          (resolve-backend-contract target)))
                      (= (aref header 19) 0)))
                (:coff
                 (and (= (aref header 0) #x64)
                      (= (aref header 1) #x86))))
        (fail "C compiler produced an object for the wrong target: ~A"
              source)))))

(defun runtime-object-name (module)
  (format nil "runtime-~(~A~).o" module))

(defun compile-runtime-modules (modules directory target)
  (loop for module in modules
        for object = (temporary-path directory (runtime-object-name module))
        do (compile-c-source (namestring (runtime-source module target))
                             object target t)
        collect object))

(defun merge-objects (objects output target)
  (run-tool (target-tool target "gcc")
            (append (list "-r" "-o" (namestring output))
                         (mapcar #'namestring objects))))

(defun emit-with-c-sources (source output target c-sources emit-psl)
  (let ((*source-location* (cdar c-sources)))
    (unless (member (target-system target) '(:linux :windows))
      (fail "FFI:SOURCE requires a supported hosted target")))
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
                 do (compile-c-source c-source c-object target))
           (merge-objects (cons psl-object c-objects) merged target)
           (sb-posix:rename (namestring merged) (namestring (pathname output)))
           output)
      (remove-temporary-directory directory names))))

(defun validate-link-inputs (kind inputs target)
  (dolist (input inputs)
    (unless (probe-file input)
      (fail "link input does not exist: ~A" input))
    (when (and (eq kind :static)
               (not (or (equalp (pathname-type input) "o")
                        (and (eq (target-system target) :windows)
                             (equalp (pathname-type input) "obj")))))
      (fail "static library inputs must be object files: ~A" input))))

(defun linker-runtime-options (target runtime-p)
  (when (and runtime-p (eq (target-system target) :linux))
    (list "-pthread")))

(defun linker-shared-options (target)
  (append (list "-shared")
          (when (eq (target-system target) :windows)
            (list "-Wl,--disable-auto-image-base,--no-insert-timestamp"))))

(defun link-artifact (object output kind inputs target &optional runtime-p)
  (validate-link-inputs kind inputs target)
  (let ((paths (cons (namestring object) (mapcar #'namestring inputs))))
    (ecase kind
      (:executable
       (run-tool (target-tool target "gcc")
                 (append (linker-runtime-options target runtime-p)
                         (when (eq (target-system target) :windows)
                           (list "-Wl,--no-insert-timestamp"))
                         (list "-o" (namestring output)) paths)))
      (:shared
       (run-tool (target-tool target "gcc")
                 (append (linker-runtime-options target runtime-p)
                         (linker-shared-options target)
                         (list "-o" (namestring output)) paths)))
      (:static
       (run-tool (target-tool target "ar")
                 (append (list "rcsD" (namestring output)) paths)))))
  output)

(defun staged-artifact-name (destination kind target)
  (if (eq (target-system target) :windows)
      (if (and (eq kind :executable)
               (not (pathname-type destination)))
          (concatenate 'string (file-namestring destination) ".exe")
          (file-namestring destination))
      "artifact"))

(defun selected-runtime-modules (runtime-roots inputs target)
  (let ((input-roots
          (mapcan (lambda (input) (input-runtime-modules input target))
                  inputs)))
    (runtime-module-closure (append runtime-roots input-roots))))

(defun link-source-artifact (output kind target inputs compile-object)
  (unless (or (and (eq (target-architecture target) :x86-64)
                   (member (target-system target) '(:linux :windows)))
              (and (eq (target-architecture target) :aarch64)
                   (eq (target-system target) :linux))
              (and (eq (target-architecture target) :riscv64)
                   (eq (target-system target) :linux)))
    (fail "linking requires a supported hosted target"))
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
         (staged-name (staged-artifact-name destination kind target))
         (staged-output (temporary-path staging-directory staged-name))
         (runtime-names nil))
    (unwind-protect
         (progn
           (validate-link-inputs kind (mapcar #'pathname inputs) target)
           (multiple-value-bind (compiled runtime-roots)
               (funcall compile-object object)
             (declare (ignore compiled))
             (let* ((modules (selected-runtime-modules
                              runtime-roots inputs target))
                    (runtime-objects nil))
               (setf runtime-names (mapcar #'runtime-object-name modules)
                     runtime-objects
                       (compile-runtime-modules modules directory target))
               (link-artifact object staged-output kind
                              (append runtime-objects
                                      (mapcar #'pathname inputs))
                              target (not (null modules)))))
           (sb-posix:rename (namestring staged-output)
                            (namestring destination))
           output)
      (remove-temporary-directory directory (cons "psl.o" runtime-names))
      (remove-temporary-directory staging-directory (list staged-name)))))
