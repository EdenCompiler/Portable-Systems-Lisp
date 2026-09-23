(in-package #:psl.compiler)

(defvar *last-hir* nil)

(defstruct source-unit source forms package locations)
(defstruct compilation source target profile signatures c-sources
           hir-functions ssa-functions lir-functions)

(defun read-unit (source)
  (multiple-value-bind (forms package locations) (read-source source)
    (make-source-unit :source source :forms forms
                      :package package :locations locations)))

(defun dispose-unit (unit)
  (when (source-unit-package unit)
    (delete-package (source-unit-package unit))
    (setf (source-unit-package unit) nil))
  unit)

(defun analyze-unit (unit &key (target "x86_64-linux-gnu")
                              (profile "freestanding"))
  (unless (source-unit-package unit)
    (fail "source unit has already been disposed"))
  (unless (member profile '("hosted" "freestanding") :test #'equal)
    (fail "unsupported profile ~A" profile))
  (let ((selected-target (if (stringp target) (resolve-target target) target))
        (*package* (source-unit-package unit)))
    (multiple-value-bind (functions signatures c-sources)
        (analyze-source (source-unit-forms unit) selected-target
                        (source-unit-locations unit))
      (unless functions (fail "source contains no functions"))
      (dolist (function functions)
        (verify-hir-function function signatures
                             (target-pointer-bits selected-target)))
      (setf *last-hir* functions)
      (make-compilation :source (source-unit-source unit)
                        :target selected-target :profile profile
                        :signatures signatures :c-sources c-sources
                        :hir-functions functions))))

(defun lower-unit (compilation)
  (let* ((bits (target-pointer-bits (compilation-target compilation)))
         (signatures (compilation-signatures compilation)))
    (dolist (function (compilation-hir-functions compilation))
      (verify-hir-function function signatures bits))
    (let ((functions (mapcar #'lower-function
                             (compilation-hir-functions compilation))))
      (dolist (function functions)
        (verify-ssa-function function signatures bits))
      (setf (compilation-ssa-functions compilation) functions)))
  compilation)

(defun optimize-unit (compilation)
  (let ((functions (compilation-ssa-functions compilation))
        (bits (target-pointer-bits (compilation-target compilation))))
    (unless functions (fail "lower the compilation before optimization"))
    (optimize-functions functions bits)
    (dolist (function functions)
      (verify-ssa-function function (compilation-signatures compilation) bits)))
  compilation)

(defun linearize-unit (compilation)
  (let ((functions (compilation-ssa-functions compilation))
        (bits (target-pointer-bits (compilation-target compilation))))
    (unless functions (fail "lower the compilation before linearization"))
    (dolist (function functions)
      (verify-ssa-function function (compilation-signatures compilation) bits))
    (let ((lir (mapcar #'linearize-function functions)))
      (dolist (function lir)
        (verify-lir-function function (compilation-signatures compilation)
                             bits))
      (setf (compilation-lir-functions compilation) lir)))
  compilation)

(defun encode-lir-functions (compilation contract)
  (let ((target (compilation-target compilation)))
    (ecase (target-architecture target)
      (:x86-64
       (mapcar (lambda (function) (compile-function function contract))
               (compilation-lir-functions compilation))))))

(defun write-target-object (encoded signatures target contract output)
  (ecase (target-object-format target)
    (:elf64 (write-elf-object encoded signatures contract output))))

(defun emit-unit (compilation output)
  (unless (compilation-lir-functions compilation)
    (fail "linearize the compilation before object emission"))
  (let* ((target (compilation-target compilation))
         (contract (resolve-backend-contract target))
         (signatures (compilation-signatures compilation))
         (c-sources (compilation-c-sources compilation)))
    (dolist (function (compilation-lir-functions compilation))
      (verify-lir-function function signatures (target-pointer-bits target)))
    (let ((encoded (encode-lir-functions compilation contract)))
      (if c-sources
          (emit-with-c-sources
           (compilation-source compilation) output target c-sources
           (lambda (path)
             (write-target-object encoded signatures target contract path)))
          (write-target-object encoded signatures target contract output)))))

(defun dump-stage (compilation stage stream)
  (ecase stage
    (:hir (mapc (lambda (function) (dump-hir-function function stream))
                (compilation-hir-functions compilation)))
    (:ssa (mapc (lambda (function) (dump-ssa-function function stream))
                (compilation-ssa-functions compilation)))
    (:lir (mapc (lambda (function) (dump-lir-function function stream))
                (compilation-lir-functions compilation)))))

(defun compile-source (source output &key (target "x86_64-linux-gnu")
                                       (profile "freestanding")
                                       (optimize t) dump-ir
                                       (dump-stream *standard-output*))
  (let ((unit (read-unit source)))
    (unwind-protect
         (let ((compilation (analyze-unit unit :target target :profile profile)))
           (when (member :hir dump-ir)
             (dump-stage compilation :hir dump-stream))
           (lower-unit compilation)
           (when optimize (optimize-unit compilation))
           (when (member :ssa dump-ir)
             (dump-stage compilation :ssa dump-stream))
           (linearize-unit compilation)
           (when (member :lir dump-ir)
             (dump-stage compilation :lir dump-stream))
           (emit-unit compilation output))
      (dispose-unit unit))))
