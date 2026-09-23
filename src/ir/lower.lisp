(in-package #:psl.ir)

(defstruct lir-instruction op dst type value args source)
(defstruct lir-function name signature instructions register-count)

(defstruct (lowering-state (:constructor make-lowering-state ()))
  (blocks nil)
  (current nil)
  (next-block 0)
  (next-value 0))

(defun new-block (state)
  (let ((block (make-ssa-block :id (lowering-state-next-block state))))
    (incf (lowering-state-next-block state))
    (push block (lowering-state-blocks state))
    block))

(defun switch-block (state block)
  (setf (lowering-state-current state) block))

(defun emit-value (state op type &key value args source)
  (let ((id (lowering-state-next-value state)))
    (incf (lowering-state-next-value state))
    (push (make-ssa-instruction :id id :op op :type type
                                :value value :args args :source source)
          (ssa-block-instructions (lowering-state-current state)))
    id))

(defun terminate-block (state op &key args targets source)
  (let ((block (lowering-state-current state)))
    (when (ssa-block-terminator block)
      (fail "internal error: block ~D already has a terminator"
            (ssa-block-id block)))
    (setf (ssa-block-terminator block)
          (make-ssa-terminator :op op :args args :targets targets
                               :source source))))

(defun lower-children (node state environment)
  (mapcar (lambda (child) (lower-hir child state environment))
          (hir-children node)))

(defun lower-variable (node environment)
  (let ((entry (assoc (hir-value node) environment :test #'equal)))
    (unless entry (fail "internal error: missing variable ~A" (hir-value node)))
    (cdr entry)))

(defun lower-let (node state environment)
  (let ((body-environment environment))
    (dolist (binding (hir-value node))
      (let ((value (lower-hir (cdr binding) state environment)))
        (push (cons (car binding) value) body-environment)))
    (lower-hir (first (hir-children node)) state body-environment)))

(defun lower-progn (node state environment)
  (loop for child in (hir-children node)
        for result = (lower-hir child state environment)
        finally (return result)))

(defun lower-if (node state environment)
  (let* ((children (hir-children node))
         (condition (first children))
         (test (lower-hir condition state environment)))
    (unless (eq (hir-type condition) :boolean)
      (return-from lower-if
        (lower-hir (second children) state environment)))
    (let ((then-block (new-block state))
          (else-block (new-block state))
          (join-block (new-block state)))
      (terminate-block state :branch :args (list test)
                       :targets (list (ssa-block-id then-block)
                                      (ssa-block-id else-block))
                       :source (hir-source node))
      (switch-block state then-block)
      (let* ((then-value (lower-hir (second children) state environment))
             (then-end (lowering-state-current state)))
        (terminate-block state :jump :targets (list (ssa-block-id join-block))
                         :source (hir-source node))
        (switch-block state else-block)
        (let* ((else-value (lower-hir (third children) state environment))
               (else-end (lowering-state-current state)))
          (terminate-block state :jump :targets (list (ssa-block-id join-block))
                           :source (hir-source node))
          (switch-block state join-block)
          (emit-value state :phi (hir-type node)
                      :args (list (cons (ssa-block-id then-end) then-value)
                                  (cons (ssa-block-id else-end) else-value))
                      :source (hir-source node)))))))

(defun lower-hir (node state environment)
  (let ((type (hir-type node))
        (source (hir-source node)))
    (case (hir-kind node)
      (:literal (emit-value state :constant type :value (hir-value node)
                            :source source))
      (:variable (lower-variable node environment))
      (:progn (lower-progn node state environment))
      (:let (lower-let node state environment))
      (:if (lower-if node state environment))
      (:binary (emit-value state :binary type :value (hir-value node)
                           :args (lower-children node state environment)
                           :source source))
      (:call (emit-value state :call type :value (hir-value node)
                         :args (lower-children node state environment)
                         :source source))
      (:field-pointer
       (emit-value state :field-pointer type :value (hir-value node)
                   :args (lower-children node state environment)
                   :source source))
      (:pointer-add
       (emit-value state :pointer-add type :value (hir-value node)
                   :args (lower-children node state environment)
                   :source source))
      (:pointer-cast
       (emit-value state :cast type
                   :args (lower-children node state environment)
                   :source source))
      (:load
       (emit-value state :load type
                   :value (pointer-volatile-p
                           (hir-type (first (hir-children node))))
                   :args (lower-children node state environment)
                   :source source))
      (:store
       (emit-value state :store type
                   :args (lower-children node state environment)
                   :source source))
      (otherwise (fail "internal error: unsupported HIR node ~A"
                       (hir-kind node))))))

(defun lower-parameters (function state)
  (loop for parameter in (function-def-parameters function)
        for index from 0
        collect (cons (car parameter)
                      (emit-value state :argument (cdr parameter)
                                  :value index
                                  :source (function-def-source function)))))

(defun lower-function (function)
  (let* ((state (make-lowering-state))
         (entry (new-block state)))
    (switch-block state entry)
    (let* ((environment (lower-parameters function state))
           (result (lower-hir (function-def-body function) state environment)))
      (terminate-block state :return :args (list result)
                       :source (function-def-source function)))
    (let ((blocks (nreverse (lowering-state-blocks state))))
      (dolist (block blocks)
        (setf (ssa-block-instructions block)
              (nreverse (ssa-block-instructions block))))
      (make-ssa-function
       :name (signature-name (function-def-signature function))
       :signature (function-def-signature function)
       :entry (ssa-block-id entry)
       :blocks blocks
       :next-value (lowering-state-next-value state)))))

(defun instruction-to-lir (instruction)
  (let* ((op (ssa-instruction-op instruction))
         (type (ssa-instruction-type instruction))
         (value (ssa-instruction-value instruction)))
    (make-lir-instruction
     :op (case op (:cast :copy) (otherwise op))
     :dst (ssa-instruction-id instruction)
     :type type
     :value (case op
              (:argument (cons value type))
              (:constant (cons value type))
              (:call (cons value type))
              (:load type)
              (:store type)
              (otherwise value))
     :args (ssa-instruction-args instruction)
     :source (ssa-instruction-source instruction))))

(defun edge-copies (function predecessor successor source)
  (let ((block (find-block function successor)))
    (loop for instruction in (ssa-block-instructions block)
          while (eq (ssa-instruction-op instruction) :phi)
          for incoming = (assoc predecessor (ssa-instruction-args instruction))
          do (unless incoming
               (fail "internal error: missing phi input from block ~D"
                     predecessor))
          collect (make-lir-instruction
                   :op :copy :dst (ssa-instruction-id instruction)
                   :type (ssa-instruction-type instruction)
                   :args (list (cdr incoming)) :source source))))

(defun terminator-to-lir (function block fresh-label)
  (let* ((terminator (ssa-block-terminator block))
         (op (ssa-terminator-op terminator))
         (targets (ssa-terminator-targets terminator))
         (source (ssa-terminator-source terminator)))
    (case op
      (:return
       (list (make-lir-instruction :op :return
                                   :type (signature-result
                                          (ssa-function-signature function))
                                   :args (ssa-terminator-args terminator)
                                   :source source)))
      (:jump
       (append (edge-copies function (ssa-block-id block) (first targets) source)
               (list (make-lir-instruction :op :jump :value (first targets)
                                           :source source))))
      (:branch
       (let ((false-edge (funcall fresh-label)))
         (append
          (list (make-lir-instruction :op :branch-zero
                                      :args (ssa-terminator-args terminator)
                                      :value false-edge :source source))
          (edge-copies function (ssa-block-id block) (first targets) source)
          (list (make-lir-instruction :op :jump :value (first targets)
                                      :source source)
                (make-lir-instruction :op :label :value false-edge
                                      :source source))
          (edge-copies function (ssa-block-id block) (second targets) source)
          (list (make-lir-instruction :op :jump :value (second targets)
                                      :source source)))))
      (otherwise (fail "internal error: unknown SSA terminator ~A" op)))))

(defun linearize-function (function)
  (let ((instructions nil)
        (next-label (1+ (reduce #'max (ssa-function-blocks function)
                                :key #'ssa-block-id))))
    (flet ((fresh-label () (prog1 next-label (incf next-label))))
      (dolist (block (ssa-function-blocks function))
        (push (make-lir-instruction :op :label :value (ssa-block-id block))
              instructions)
        (dolist (instruction (ssa-block-instructions block))
          (unless (eq (ssa-instruction-op instruction) :phi)
            (push (instruction-to-lir instruction) instructions)))
        (dolist (instruction (terminator-to-lir function block #'fresh-label))
          (push instruction instructions))))
    (make-lir-function :name (ssa-function-name function)
                       :signature (ssa-function-signature function)
                       :instructions (nreverse instructions)
                       :register-count (ssa-function-next-value function))))
