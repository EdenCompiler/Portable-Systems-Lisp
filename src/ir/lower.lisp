(in-package #:psl.ir)

(defstruct lir-instruction op dst value args)
(defstruct lir-function name instructions register-count)
(defstruct (lowering (:constructor make-lowering ()))
  (instructions nil)
  (next-register 0)
  (next-label 0))

(defun new-register (state)
  (prog1 (lowering-next-register state)
    (incf (lowering-next-register state))))

(defun new-label (state)
  (prog1 (lowering-next-label state)
    (incf (lowering-next-label state))))

(defun emit-lir (state op &key dst value args)
  (push (make-lir-instruction :op op :dst dst :value value :args args)
        (lowering-instructions state)))

(defun lower-literal (node state)
  (let ((result (new-register state)))
    (emit-lir state :constant :dst result
              :value (cons (hir-value node) (hir-type node)))
    result))

(defun lower-variable (node environment)
  (let ((register (cdr (assoc (hir-value node) environment :test #'equal))))
    (unless register
      (error "PSL internal error: missing variable ~A" (hir-value node)))
    register))

(defun lower-progn (node state environment)
  (loop for child in (hir-children node)
        for result = (lower-hir child state environment)
        finally (return result)))

(defun lower-let (node state environment)
  (let ((body-environment environment))
    (dolist (binding (hir-value node))
      (let ((value (lower-hir (cdr binding) state environment)))
        (push (cons (car binding) value) body-environment)))
    (lower-hir (first (hir-children node)) state body-environment)))

(defun lower-binary (node state environment)
  (let* ((operands (mapcar (lambda (child)
                             (lower-hir child state environment))
                           (hir-children node)))
         (result (new-register state)))
    (emit-lir state :binary :dst result :value (hir-value node)
              :args operands)
    result))

(defun lower-if (node state environment)
  (let ((condition (first (hir-children node))))
    (let ((test (lower-hir condition state environment)))
      (unless (eq (hir-type condition) :boolean)
        ;; All machine integers, including zero, are true in Common Lisp.
        (return-from lower-if
          (lower-hir (second (hir-children node)) state environment)))
      (let ((otherwise-label (new-label state))
            (end-label (new-label state))
            (result (new-register state)))
        (emit-lir state :branch-zero :value otherwise-label :args (list test))
        (emit-lir state :copy :dst result
                  :args (list (lower-hir (second (hir-children node))
                                         state environment)))
        (emit-lir state :jump :value end-label)
        (emit-lir state :label :value otherwise-label)
        (emit-lir state :copy :dst result
                  :args (list (lower-hir (third (hir-children node))
                                         state environment)))
        (emit-lir state :label :value end-label)
        result))))

(defun lower-call (node state environment)
  (let* ((arguments (mapcar (lambda (child)
                              (lower-hir child state environment))
                            (hir-children node)))
         (result (new-register state)))
    (emit-lir state :call :dst result
              :value (cons (hir-value node) (hir-type node))
              :args arguments)
    result))

(defun lower-unary (node state environment operation)
  (let ((source (lower-hir (first (hir-children node)) state environment))
        (result (new-register state)))
    (emit-lir state operation :dst result
              :value (if (eq operation :load) (hir-type node) (hir-value node))
              :args (list source))
    result))

(defun lower-pointer-add (node state environment)
  (let* ((arguments (mapcar (lambda (child)
                              (lower-hir child state environment))
                            (hir-children node)))
         (result (new-register state)))
    (emit-lir state :pointer-add :dst result :value (hir-value node)
              :args arguments)
    result))

(defun lower-store (node state environment)
  (let ((arguments (mapcar (lambda (child)
                             (lower-hir child state environment))
                           (hir-children node)))
        (result (new-register state)))
    (emit-lir state :store :dst result :value (hir-type node)
              :args arguments)
    result))

(defun lower-hir (node state environment)
  (case (hir-kind node)
    (:literal (lower-literal node state))
    (:variable (lower-variable node environment))
    (:progn (lower-progn node state environment))
    (:let (lower-let node state environment))
    (:binary (lower-binary node state environment))
    (:if (lower-if node state environment))
    (:call (lower-call node state environment))
    (:field-pointer (lower-unary node state environment :field-pointer))
    (:pointer-add (lower-pointer-add node state environment))
    (:pointer-cast
     (lower-hir (first (hir-children node)) state environment))
    (:load (lower-unary node state environment :load))
    (:store (lower-store node state environment))
    (otherwise (error "PSL internal error: unsupported HIR node ~A"
                      (hir-kind node)))))

(defun lower-parameters (function state)
  (loop for parameter in (function-def-parameters function)
        for index from 0
        for register = (new-register state)
        do (emit-lir state :argument :dst register
                     :value (cons index (cdr parameter)))
        collect (cons (car parameter) register)))

(defun lower-function (function)
  (let* ((state (make-lowering))
         (environment (lower-parameters function state))
         (result (lower-hir (function-def-body function) state environment)))
    (emit-lir state :return :args (list result))
    (make-lir-function
     :name (signature-name (function-def-signature function))
     :instructions (nreverse (lowering-instructions state))
     :register-count (lowering-next-register state))))
