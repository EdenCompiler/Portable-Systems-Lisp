(in-package #:psl.compiler)

(defvar *last-hir* nil)

(defun encode-functions (functions target)
  (ecase (target-architecture target)
    (:x86-64 (mapcar #'compile-function (mapcar #'lower-function functions)))))

(defun emit-object (functions signatures target output)
  (ecase (target-object-format target)
    (:elf64 (write-elf-object functions signatures output))))

(defun emit-compilation-unit (source output target functions signatures c-sources)
  (let ((encoded (encode-functions functions target)))
    (if c-sources
        (emit-with-c-sources
         source output target c-sources
         (lambda (path) (emit-object encoded signatures target path)))
        (emit-object encoded signatures target output))))

(defun compile-source (source output &key (target "x86_64-linux-gnu")
                                       (profile "freestanding"))
  (unless (member profile '("hosted" "freestanding") :test #'equal)
    (fail "unsupported profile ~A" profile))
  (let ((selected-target (resolve-target target)))
    (multiple-value-bind (forms source-package) (read-source source)
      (unwind-protect
           (multiple-value-bind (functions signatures c-sources)
               (analyze-source forms selected-target)
             (unless functions (fail "source contains no functions"))
             (setf *last-hir* functions)
             (emit-compilation-unit source output selected-target
                                    functions signatures c-sources))
        (delete-package source-package)))))
