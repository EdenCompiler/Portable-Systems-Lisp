(in-package #:psl.frontend)

(defun source-package-name (form)
  (unless (or (symbolp form) (stringp form))
    (fail "source package names must be symbols or strings"))
  (string form))

(defun source-define-package (form)
  (unless (>= (length form) 2)
    (fail "DEFPACKAGE requires a package name"))
  (let ((name (source-package-name (second form))))
    (when (find-package name)
      (fail "source package already exists: ~A" name))
    (dolist (option (cddr form))
      (unless (and (consp option)
                   (member (first option)
                           '(:nicknames :use :shadow :shadowing-import-from
                             :import-from :intern :export)))
        (fail "unsupported source DEFPACKAGE option ~S" option))
      (when (and (member (first option) '(:import-from :shadowing-import-from))
                 (null (rest option)))
        (fail "package import option requires a package name"))
      (dolist (item (rest option)) (source-package-name item)))
    ;; A failed host DEFPACKAGE can create its package before signalling.
    ;; Track that package too, so the compilation environment always disposes it.
    (unwind-protect
         (eval form)
      (let ((package (find-package name)))
        (when package (pushnew package *source-packages*))))))

(defun source-select-package (form)
  (unless (= (length form) 2)
    (fail "IN-PACKAGE requires one package name"))
  (let* ((name (source-package-name (second form)))
         (package (find-package name)))
    (unless package (fail "source package does not exist: ~A" name))
    (setf *package* package)))

(defun dispose-source-packages (packages)
  (dolist (package packages)
    (when (package-name package) (delete-package package))))
