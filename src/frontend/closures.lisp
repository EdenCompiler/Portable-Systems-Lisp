(in-package #:psl.frontend)

(defun visible-bindings (environment argument-name)
  (let ((seen (list argument-name)) (captures nil))
    (dolist (entry environment)
      (unless (member (car entry) seen :test #'equal)
        (push (car entry) seen)
        (push entry captures)))
    (nreverse captures)))

(defun free-hir-names (node &optional bound)
  (case (hir-kind node)
    (:variable
     (unless (member (hir-value node) bound :test #'equal)
       (list (hir-value node))))
    (:let
     (append (mapcan (lambda (entry) (free-hir-names (cdr entry) bound))
                     (hir-value node))
             (free-hir-names (first (hir-children node))
                             (append (mapcar #'car (hir-value node)) bound))))
    (otherwise
     (mapcan (lambda (child) (free-hir-names child bound))
             (hir-children node)))))

(defun required-value-captures (visible body argument-name)
  (let ((names (free-hir-names body (list argument-name))))
    (loop for entry in visible
          when (member (car entry) names :test #'equal)
            do (unless (eq (cdr entry) :value)
                 (fail "closures currently capture only VALUE variables: ~A"
                       (car entry)))
            and collect entry)))

(defun runtime-call-node (name argument-types result module effect arguments
                          context)
  (make-hir :kind :call :type result
            :value (register-runtime-call name argument-types result
                                          module effect context)
            :children arguments :source *source-location*))

(defun capture-list-node (captures context)
  (reduce (lambda (entry rest)
            (runtime-call-node
             "psl_rt_cons" '(:value :value) :value :cons :allocates
             (list (make-hir :kind :variable :type :value :value (car entry))
                   rest)
             context))
          captures
          :from-end t
          :initial-value (make-hir :kind :literal :type :value :value 2)))

(defun captured-binding-nodes (captures context)
  (let ((tail (make-hir :kind :variable :type :value
                        :value "%closure-environment"))
        (bindings nil))
    (dolist (entry captures)
      (push (cons (car entry)
                  (runtime-call-node "psl_rt_car" '(:value) :value
                                     :cons :none (list tail) context))
            bindings)
      (setf tail (runtime-call-node "psl_rt_cdr" '(:value) :value
                                    :cons :none (list tail) context)))
    (nreverse bindings)))

(defun next-lambda-name (context)
  (prog1 (format nil "psl_lambda_~D"
                 (analysis-context-lambda-counter context))
    (incf (analysis-context-lambda-counter context))))

(defun analyze-lambda-expression (form environment context)
  (require-hosted-runtime context)
  (unless (and (>= (length form) 3)
               (listp (second form)) (= (length (second form)) 1)
               (symbolp (first (second form))))
    (fail "hosted closures currently require one simple parameter"))
  (let* ((argument-name (source-name (first (second form))))
         (visible (visible-bindings environment argument-name))
         (name (next-lambda-name context))
         (parameters (list (cons "%closure-environment" :value)
                           (cons argument-name :value)))
         (signature (make-signature :name name :arguments '(:value :value)
                                    :result :value :external-p nil
                                    :local-p t))
         (body-environment (append (list (cons argument-name :value))
                                   visible))
         (body (analyze-progn (cddr form) body-environment context :value))
         (captures (required-value-captures visible body argument-name))
         (bindings (captured-binding-nodes captures context))
         (wrapped (if bindings
                      (make-hir :kind :let :type :value :value bindings
                                :children (list body))
                      body)))
    (when (gethash name (analysis-context-signatures context))
      (fail "generated closure name conflicts with ~A" name))
    (setf (gethash name (analysis-context-signatures context)) signature)
    (push (make-function-def :signature signature :parameters parameters
                             :body wrapped :source *source-location*)
          (analysis-context-generated-functions context))
    (runtime-call-node
     "psl_rt_make_closure" '((:ptr :void nil nil) :value)
     :value :closure :allocates
     (list (make-hir :kind :data-address :type '(:ptr :void nil nil)
                     :value (cons name :void))
           (capture-list-node captures context))
     context)))
