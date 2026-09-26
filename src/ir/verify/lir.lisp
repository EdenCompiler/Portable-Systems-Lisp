(in-package #:psl.ir)

(defun lir-register-types (function)
  (let ((types (make-hash-table))
        (count (lir-function-register-count function)))
    (dolist (instruction (lir-function-instructions function))
      (let ((id (lir-instruction-dst instruction))
            (type (lir-instruction-type instruction)))
        (when id
          (unless (and (integerp id) (<= 0 id) (< id count)
                       (valid-type-p type))
            (fail "invalid LIR destination register or type"))
          (let ((previous (gethash id types)))
            (when previous
              (expect-same-type type previous "LIR register")))
          (setf (gethash id types) type))))
    types))

(defun lir-operand-types (instruction register-types)
  (mapcar (lambda (id)
            (unless (and (integerp id) (gethash id register-types))
              (fail "LIR uses undefined register ~S" id))
            (gethash id register-types))
          (lir-instruction-args instruction)))

(defvar *verifying-lir* nil)

(defun verify-lir-operation (instruction register-types signatures pointer-bits)
  (let* ((*source-location* (or (lir-instruction-source instruction)
                                *source-location*))
         (op (lir-instruction-op instruction))
         (type (lir-instruction-type instruction))
         (types (lir-operand-types instruction register-types))
         (value (lir-instruction-value instruction)))
    (case op
      (:label (expect-count types 0 "LIR label"))
      (:jump (expect-count types 0 "LIR jump"))
      (:branch-zero
       (expect-count types 1 "LIR branch")
       (expect-same-type (first types) :boolean "LIR branch condition"))
      (:return
       (expect-count types 1 "LIR return")
       (expect-same-type (first types) type "LIR return"))
      (:argument
       (expect-count types 0 "LIR argument")
       (unless (and (consp value)
                    (integerp (car value))
                    (<= 0 (car value))
                    (< (car value)
                       (length (signature-arguments
                                (lir-function-signature *verifying-lir*)))))
         (fail "invalid LIR argument index"))
       (expect-same-type
        type (nth (car value)
                  (signature-arguments (lir-function-signature *verifying-lir*)))
        "LIR argument"))
      (:constant
       (expect-count types 0 "LIR constant")
       (unless (and (consp value) (equal (cdr value) type)
                    (literal-fits-p (car value) type pointer-bits))
         (fail "invalid LIR constant")))
      (:copy
       (expect-count types 1 "LIR copy")
       (unless (equal type (first types))
         (fail "LIR copy type mismatch")))
      (:convert
       (expect-count types 1 "LIR conversion")
       (unless (or (and (integer-type-p type)
                        (integer-type-p (first types)))
                   (and (pointer-type-p type)
                        (or (pointer-type-p (first types))
                            (eq (first types) :usize))))
         (fail "invalid LIR conversion")))
      (:binary
       (verify-ssa-binary
        (make-ssa-instruction :op :binary :type type :value value)
        types))
      (:call
       (verify-ssa-call
        (make-ssa-instruction :op :call :type type :value (car value))
        types signatures))
      (:data-address
       (expect-count types 0 "LIR data address")
       (unless (and (consp value) (stringp (car value))
                    (pointer-type-p type)
                    (equal (pointed-type type) (cdr value)))
         (fail "invalid LIR data address")))
      ((:field-pointer :pointer-add :load :store)
       (verify-ssa-memory
        (make-ssa-instruction :op op :type type
                              :value (if (eq op :load)
                                         (pointer-volatile-p (first types))
                                         value))
        types))
      (otherwise (fail "unknown LIR instruction ~S" op)))))

(defun lir-label-indices (instructions)
  (let ((labels (make-hash-table)))
    (loop for instruction across instructions
          for index from 0
          when (eq (lir-instruction-op instruction) :label)
            do (let ((id (lir-instruction-value instruction)))
                 (unless (and (integerp id) (<= 0 id))
                   (fail "invalid LIR label"))
                 (when (gethash id labels)
                   (fail "duplicate LIR label ~D" id))
                 (setf (gethash id labels) index)))
    labels))

(defun lir-successors (instructions index labels)
  (let* ((instruction (aref instructions index))
         (op (lir-instruction-op instruction))
         (next (and (< (1+ index) (length instructions)) (1+ index))))
    (case op
      (:return nil)
      (:jump (list (gethash (lir-instruction-value instruction) labels)))
      (:branch-zero
       (remove nil (list (gethash (lir-instruction-value instruction) labels)
                         next)))
      (otherwise (if next (list next) nil)))))

(defun lir-flow (instructions labels)
  (let* ((count (length instructions))
         (successors (make-array count))
         (predecessors (make-array count :initial-element nil))
         (reachable (make-array count :initial-element nil)))
    (dotimes (index count)
      (setf (aref successors index)
            (lir-successors instructions index labels))
      (dolist (next (aref successors index))
        (push index (aref predecessors next))))
    (let ((pending (list 0)))
      (loop while pending
            for index = (pop pending)
            unless (aref reachable index)
              do (setf (aref reachable index) t)
                 (dolist (next (aref successors index))
                   (push next pending))))
    (values predecessors reachable successors)))

(defun verify-lir-assignment (instructions labels register-count)
  (multiple-value-bind (predecessors reachable successors)
      (lir-flow instructions labels)
    (let* ((count (length instructions))
           (all (loop for id below register-count collect id))
           (inputs (make-array count))
           (outputs (make-array count)))
      (dotimes (index count)
        (setf (aref inputs index) (if (zerop index) nil (copy-list all))
              (aref outputs index) (copy-list all)))
      (loop with changed = t
            while changed
            do (setf changed nil)
               (dotimes (index count)
                 (when (aref reachable index)
                   (let* ((preds (remove-if-not
                                  (lambda (item) (aref reachable item))
                                  (aref predecessors index)))
                          (in (if (zerop index)
                                  nil
                                  (if preds
                                      (reduce #'intersection preds
                                              :key (lambda (item)
                                                     (aref outputs item)))
                                      nil)))
                          (dst (lir-instruction-dst (aref instructions index)))
                          (out (if dst (adjoin dst in) in)))
                     (unless (and (set-equal in (aref inputs index))
                                  (set-equal out (aref outputs index)))
                       (setf (aref inputs index) in
                             (aref outputs index) out
                             changed t))))))
      (dotimes (index count)
        (when (aref reachable index)
          (when (and (null (aref successors index))
                     (not (eq (lir-instruction-op (aref instructions index))
                              :return)))
            (fail "LIR control flow reaches the end without a return"))
          (dolist (used (lir-instruction-args (aref instructions index)))
            (unless (member used (aref inputs index))
              (fail "LIR register ~D may be used before assignment" used)))))))
  t)

(defun verify-lir-function (function signatures pointer-bits)
  (unless (lir-function-p function) (fail "expected a LIR function"))
  (unless (equal (lir-function-name function)
                 (signature-name (lir-function-signature function)))
    (fail "LIR function name differs from signature"))
  (let* ((*verifying-lir* function)
         (instructions (coerce (lir-function-instructions function) 'vector))
         (register-types (lir-register-types function))
         (labels (lir-label-indices instructions)))
    (unless (plusp (length instructions)) (fail "empty LIR function"))
    (loop for instruction across instructions
          do (when (member (lir-instruction-op instruction)
                           '(:jump :branch-zero))
               (unless (gethash (lir-instruction-value instruction) labels)
                 (fail "LIR branch targets undefined label ~S"
                       (lir-instruction-value instruction))))
             (when (eq (lir-instruction-op instruction) :return)
               (expect-same-type
                (lir-instruction-type instruction)
                (signature-result (lir-function-signature function))
                "LIR return"))
             (verify-lir-operation instruction register-types
                                   signatures pointer-bits))
    (verify-lir-assignment instructions labels
                           (lir-function-register-count function)))
  t)
