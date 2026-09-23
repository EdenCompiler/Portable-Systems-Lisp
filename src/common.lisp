(in-package #:psl.common)

(defun fail (control &rest arguments)
  (error "PSL: ~A" (apply #'format nil control arguments)))
