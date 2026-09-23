(in-package #:psl.frontend)

(defun hir-nested-nodes (node)
  (if (eq (hir-kind node) :let)
      (append (mapcar #'cdr (hir-value node)) (hir-children node))
      (hir-children node)))

(defun hir-call-names (node)
  (append (when (eq (hir-kind node) :call) (list (hir-value node)))
          (mapcan #'hir-call-names (hir-nested-nodes node))))

(defun call-allocation-free-p (name signatures safe-functions)
  (let ((signature (gethash name signatures)))
    (and signature
         (if (signature-external-p signature)
             (eq (signature-effect signature) :none)
             (gethash name safe-functions)))))

(defun function-allocation-free-p (function signatures safe-functions)
  (every (lambda (name)
           (call-allocation-free-p name signatures safe-functions))
         (hir-call-names (function-def-body function))))

(defun allocation-free-functions (functions signatures)
  (let ((safe (make-hash-table :test #'equal)))
    (dolist (function functions)
      (setf (gethash (signature-name (function-def-signature function)) safe) t))
    (loop with changed = t
          while changed
          do (setf changed nil)
             (dolist (function functions)
               (let ((name (signature-name (function-def-signature function))))
                 (when (and (gethash name safe)
                            (not (function-allocation-free-p
                                  function signatures safe)))
                   (setf (gethash name safe) nil
                         changed t)))))
    safe))

(defun verify-allocation-region (region signatures safe-functions)
  (let ((unsafe
          (find-if-not
           (lambda (name)
             (call-allocation-free-p name signatures safe-functions))
           (hir-call-names region))))
    (when unsafe
      (let ((*source-location* (hir-source region)))
        (fail "WITHOUT-ALLOCATION cannot certify call to ~A" unsafe)))))

(defun verify-allocation-regions (functions context)
  (let* ((signatures (analysis-context-signatures context))
         (safe (allocation-free-functions functions signatures)))
    (dolist (region (analysis-context-allocation-regions context))
      (verify-allocation-region region signatures safe))))
