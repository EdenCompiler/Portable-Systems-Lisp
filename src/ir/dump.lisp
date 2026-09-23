(in-package #:psl.ir)

(defun source-suffix (source)
  (if source (format nil " @ ~A" (location-label source)) ""))

(defun dump-hir-node (node stream depth)
  (format stream "~VT~A ~S~@[ ~S~]~A~%"
          (* depth 2) (hir-kind node) (hir-type node)
          (unless (eq (hir-kind node) :let) (hir-value node))
          (source-suffix (hir-source node)))
  (when (eq (hir-kind node) :let)
    (dolist (binding (hir-value node))
      (format stream "~VTbinding ~A~%" (* (1+ depth) 2) (car binding))
      (dump-hir-node (cdr binding) stream (+ depth 2))))
  (dolist (child (hir-children node))
    (dump-hir-node child stream (1+ depth))))

(defun dump-hir-function (function &optional (stream *standard-output*))
  (format stream "HIR ~A ~S -> ~S~%"
          (signature-name (function-def-signature function))
          (function-def-parameters function)
          (signature-result (function-def-signature function)))
  (dump-hir-node (function-def-body function) stream 1))

(defun dump-ssa-function (function &optional (stream *standard-output*))
  (format stream "SSA ~A entry=b~D~%"
          (ssa-function-name function) (ssa-function-entry function))
  (dolist (block (ssa-function-blocks function))
    (format stream "  b~D:~%" (ssa-block-id block))
    (dolist (instruction (ssa-block-instructions block))
      (format stream "    %~D = ~A ~S value=~S args=~S~A~%"
              (ssa-instruction-id instruction)
              (ssa-instruction-op instruction)
              (ssa-instruction-type instruction)
              (ssa-instruction-value instruction)
              (ssa-instruction-args instruction)
              (source-suffix (ssa-instruction-source instruction))))
    (let ((terminator (ssa-block-terminator block)))
      (format stream "    ~A args=~S targets=~S~A~%"
              (ssa-terminator-op terminator)
              (ssa-terminator-args terminator)
              (ssa-terminator-targets terminator)
              (source-suffix (ssa-terminator-source terminator))))))

(defun dump-lir-function (function &optional (stream *standard-output*))
  (format stream "LIR ~A registers=~D~%"
          (lir-function-name function) (lir-function-register-count function))
  (dolist (instruction (lir-function-instructions function))
    (format stream "  ~A~@[ %~D~]~@[ ~S~] value=~S args=~S~A~%"
            (lir-instruction-op instruction)
            (lir-instruction-dst instruction)
            (lir-instruction-type instruction)
            (lir-instruction-value instruction)
            (lir-instruction-args instruction)
            (source-suffix (lir-instruction-source instruction)))))
