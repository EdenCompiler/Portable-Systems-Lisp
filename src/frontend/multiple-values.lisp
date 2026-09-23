(in-package #:psl.frontend)

(defun analyze-values2 (form environment context)
  (require-hosted-runtime context)
  (unless (= (length form) 3)
    (fail "Stage 0 VALUES currently requires two arguments"))
  (let ((arguments
          (mapcar (lambda (source)
                    (analyze-expression source environment context :value))
                  (rest form))))
    (unless (every (lambda (node) (eq (hir-type node) :value)) arguments)
      (fail "VALUES arguments must have type VALUE"))
    (runtime-call-node "psl_rt_values2" '(:value :value) :value
                       :values :allocates arguments context)))

(defun analyze-multiple-value-bind (form environment context expected)
  (require-hosted-runtime context)
  (unless (and (>= (length form) 4)
               (listp (second form))
               (= (length (second form)) 2)
               (every #'symbolp (second form))
               (form-p (third form) "values"))
    (fail "Stage 0 MULTIPLE-VALUE-BIND needs two names and a VALUES form"))
  (let* ((names (mapcar #'source-name (second form)))
         (first-value (analyze-values2 (third form) environment context))
         (second-value
           (runtime-call-node
            "psl_rt_nth_value" '(:usize) :value :values :none
            (list (make-hir :kind :literal :type :usize :value 1)) context))
         (bindings (mapcar #'cons names (list first-value second-value)))
         (body-environment
           (append (mapcar (lambda (name) (cons name :value)) names)
                   environment))
         (body (analyze-progn (cdddr form) body-environment context expected)))
    (when (equal (first names) (second names))
      (fail "MULTIPLE-VALUE-BIND names must be distinct"))
    (make-hir :kind :let :type (hir-type body) :value bindings
              :children (list body))))
