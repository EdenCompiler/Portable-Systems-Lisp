(in-package #:psl.ffi.toolchain)

(defparameter *linker-directory*
  (merge-pathnames "../../linker/"
                   (make-pathname :name nil :type nil
                                  :defaults *load-truename*)))

(defun default-freestanding-script (target)
  (merge-pathnames
   (ecase (target-architecture target)
     (:x86-64 "x86_64-linux-user.ld")
     (:riscv64 "riscv64-virt.ld"))
   *linker-directory*))

(defun startup-function (target startup)
  (case startup
    (:linux-exit
     (unless (eq (target-architecture target) :x86-64)
       (fail "linux-exit startup requires x86_64-none-elf"))
     (psl.backend.x86-64:compile-linux-exit-startup))
    (:qemu-virt
     (unless (eq (target-architecture target) :riscv64)
       (fail "qemu-virt startup requires riscv64-none-elf"))
     (psl.backend.riscv64:compile-qemu-virt-startup))
    (otherwise (fail "unsupported freestanding startup ~A" startup))))

(defun write-startup-object (target startup path)
  (let ((signatures (make-hash-table :test #'equal)))
    (setf (gethash "_start" signatures)
          (psl.ir:make-signature :name "_start" :arguments nil
                                 :result :void :external-p nil)
          (gethash "main" signatures)
          (psl.ir:make-signature :name "main" :arguments nil
                                 :result :s32 :external-p t))
    (psl.object.elf64:write-elf-object
     (list (startup-function target startup)) signatures nil
     (resolve-backend-contract target) path)))

(defun freestanding-link-inputs (object startup-object inputs)
  (append (when startup-object (list startup-object))
          (list object)
          (mapcar #'pathname inputs)))

(defun freestanding-link-arguments (destination objects entry script map)
  (append (list "-nostdlib" "-static" "--build-id=none"
                "--fatal-warnings"
                "-e" entry)
          (when script (list "-T" (namestring (pathname script))))
          (when map (list "-Map" (namestring (pathname map))))
          (list "-o" (namestring destination))
          (mapcar #'namestring objects)))

(defun link-freestanding-executable (output target inputs compile-object
                                     startup linker-script entry map-file)
  (let* ((directory (temporary-directory))
         (object (temporary-path directory "psl.o"))
         (startup-object (when startup (temporary-path directory "startup.o")))
         (destination (merge-pathnames output (truename ".")))
         (destination-directory
           (make-pathname :name nil :type nil :defaults destination))
         (staging-directory
           (sb-posix:mkdtemp
            (format nil "~A/.psl-link-XXXXXX"
                    (string-right-trim "/"
                                       (namestring destination-directory)))))
         (staged-output (temporary-path staging-directory "artifact"))
         (script (or linker-script (default-freestanding-script target))))
    (unwind-protect
         (progn
           (unless (probe-file script)
             (fail "linker script does not exist: ~A" script))
           (multiple-value-bind (compiled runtime-roots)
               (funcall compile-object object)
             (declare (ignore compiled))
             (when runtime-roots
               (fail "freestanding executable requires no hosted runtime")))
           (when startup
             (write-startup-object target startup startup-object))
           (run-tool (target-tool target "ld")
                     (freestanding-link-arguments
                      staged-output
                      (freestanding-link-inputs object startup-object inputs)
                      entry script map-file))
           (sb-posix:rename (namestring staged-output)
                            (namestring destination))
           output)
      (remove-temporary-directory directory
                                  (if startup '("psl.o" "startup.o")
                                      '("psl.o")))
      (remove-temporary-directory staging-directory '("artifact")))))

(defun link-freestanding-artifact (output kind target inputs compile-object
                                   &key profile startup linker-script
                                     (entry "_start") map-file)
  (unless (and (eq (target-system target) :none)
               (equal profile "freestanding"))
    (fail "freestanding linking requires a none target and profile"))
  (unless (eq kind :executable)
    (fail "freestanding linking currently produces executables only"))
  (when (and startup (not (equal entry "_start")))
    (fail "generated startup requires entry _start"))
  (validate-link-inputs kind inputs target)
  (link-freestanding-executable
   output target inputs compile-object startup linker-script entry map-file))
