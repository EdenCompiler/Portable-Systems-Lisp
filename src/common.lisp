(in-package #:psl.common)

(defstruct source-location path line column)
(defvar *source-location* nil)

(defun location-label (location)
  (format nil "~A:~D:~D"
          (source-location-path location)
          (source-location-line location)
          (source-location-column location)))

(defun fail (control &rest arguments)
  (error "PSL: ~@[~A: ~]~A"
         (when *source-location* (location-label *source-location*))
         (apply #'format nil control arguments)))
