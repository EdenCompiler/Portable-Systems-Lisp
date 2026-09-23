(in-package #:psl.ir)

(defstruct ssa-instruction id op type value args source)
(defstruct ssa-terminator op args targets source)
(defstruct ssa-block id instructions terminator)
(defstruct ssa-function name signature blocks entry next-value)

(defun find-block (function id)
  (find id (ssa-function-blocks function) :key #'ssa-block-id))

(defun block-successors (block)
  (ssa-terminator-targets (ssa-block-terminator block)))

(defun block-predecessors (function id)
  (loop for block in (ssa-function-blocks function)
        when (member id (block-successors block))
          collect (ssa-block-id block)))

(defun ssa-definitions (function)
  (let ((definitions (make-hash-table)))
    (dolist (block (ssa-function-blocks function))
      (dolist (instruction (ssa-block-instructions block))
        (setf (gethash (ssa-instruction-id instruction) definitions)
              instruction)))
    definitions))
