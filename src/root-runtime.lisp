(in-package #:psl.compiler)

(defun register-root-signature (signatures name arguments)
  (let ((prior (gethash name signatures)))
    (when (and prior
               (not (and (signature-external-p prior)
                         (equal (signature-arguments prior) arguments)
                         (eq (signature-result prior) :void)
                         (eq (signature-effect prior) :none))))
      (fail "root runtime symbol ~A conflicts with a source declaration" name))
    (unless prior
      (setf (gethash name signatures)
            (make-signature :name name :arguments arguments :result :void
                            :external-p t :effect :none)))))

(defun register-root-runtime (compilation)
  (unless (equal (compilation-profile compilation) "hosted")
    (fail "managed root frames require the hosted profile"))
  (dolist (data (compilation-data compilation))
    (when (member (data-declaration-name data)
                  '("psl_rt_push_roots" "psl_rt_pop_roots") :test #'equal)
      (fail "root runtime symbol conflicts with a data declaration")))
  (let ((signatures (compilation-signatures compilation)))
    (register-root-signature signatures "psl_rt_push_roots"
                             '((:ptr :void nil nil) (:ptr :value nil nil) :usize))
    (register-root-signature signatures "psl_rt_pop_roots" '((:ptr :void nil nil)))
    (pushnew :gc (compilation-runtime-modules compilation))))
