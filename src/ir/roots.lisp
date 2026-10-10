(in-package #:psl.ir)

(defun managed-registers (types)
  (sort (loop for id being the hash-keys of types using (hash-value type)
              when (eq type :value) collect id) #'<))

(defun lir-safepoint-p (instruction signatures)
  (and (eq (lir-instruction-op instruction) :call)
       (let ((signature (gethash (car (lir-instruction-value instruction)) signatures)))
         (or (null signature) (not (eq (signature-effect signature) :none))))))

(defun lir-needs-root-frame-p (function signatures types)
  (and (managed-registers types)
       (some (lambda (instruction) (lir-safepoint-p instruction signatures))
             (lir-function-instructions function))))

(defun root-operation (op)
  (make-lir-instruction :op op))

(defun lower-root-frames (function signatures)
  (when (lir-function-root-registers function)
    (return-from lower-root-frames function))
  (let ((types (lir-register-types function)))
    (when (lir-needs-root-frame-p function signatures types)
      (let ((result (list (root-operation :roots-init))) (entered nil))
        (dolist (instruction (lir-function-instructions function))
          (let ((op (lir-instruction-op instruction)))
            (unless (or entered (member op '(:label :argument)))
              (push (root-operation :roots-enter) result)
              (setf entered t))
            (when (eq op :call) (push (root-operation :roots-sync) result))
            (when (eq op :return) (push (root-operation :roots-leave) result))
            (push instruction result)))
        (setf (lir-function-root-registers function) (managed-registers types)
              (lir-function-instructions function) (nreverse result)))))
  function)

(defun root-state-after (op state)
  (case op
    (:roots-init
     (unless (eq state :uninitialized) (fail "duplicate LIR root initialization"))
     :ready)
    (:roots-enter
     (unless (eq state :ready) (fail "invalid LIR root entry"))
     :active)
    (:roots-sync
     (unless (eq state :active) (fail "LIR roots synchronized outside frame"))
     :active)
    (:roots-leave
     (unless (eq state :active) (fail "invalid LIR root exit"))
     :closed)
    (:argument
     (unless (eq state :ready) (fail "LIR argument follows root registration"))
     :ready)
    (:call
     (unless (eq state :active) (fail "LIR call outside root frame"))
     :active)
    (:return
     (unless (eq state :closed) (fail "LIR return leaves root frame active"))
     :closed)
    (otherwise state)))

(defun verify-root-flow (instructions labels)
  (multiple-value-bind (predecessors reachable successors)
      (lir-flow instructions labels)
    (declare (ignore predecessors))
    (let ((states (make-array (length instructions) :initial-element nil))
          (pending (list 0)))
      (setf (aref states 0) :uninitialized)
      (loop while pending
            for index = (pop pending)
            for instruction = (aref instructions index)
            for state = (root-state-after (lir-instruction-op instruction)
                                          (aref states index))
            do (dolist (next (aref successors index))
                 (let ((prior (aref states next)))
                   (when (and prior (not (eq prior state)))
                     (fail "inconsistent LIR root lifetime at control-flow join"))
                   (unless prior
                     (setf (aref states next) state)
                     (push next pending)))))
      (dotimes (index (length instructions))
        (when (and (aref reachable index)
                   (eq (lir-instruction-op (aref instructions index)) :call))
          (unless (and (plusp index)
                       (eq (lir-instruction-op (aref instructions (1- index)))
                           :roots-sync))
            (fail "LIR call lacks root synchronization")))))))

(defun verify-lir-roots (function types signatures instructions labels)
  (let ((roots (lir-function-root-registers function)))
    (if roots
        (progn
          (unless (equal roots (managed-registers types))
            (fail "LIR root catalogue differs from managed register types"))
          (unless (eq (lir-instruction-op (aref instructions 0)) :roots-init)
            (fail "LIR root initialization must precede labels and arguments"))
          (verify-root-flow instructions labels))
        (progn
          (when (lir-needs-root-frame-p function signatures types)
            (fail "managed LIR safepoint has no root frame"))
          (when (find-if (lambda (instruction)
                          (member (lir-instruction-op instruction)
                                  '(:roots-init :roots-enter :roots-sync :roots-leave)))
                        (lir-function-instructions function))
            (fail "LIR root operations lack a root catalogue")))))
  t)
