(in-package #:psl.frontend)

(defun source-check-macro-variable (variable)
  (when (and (symbolp variable) (constantp variable))
    (error "constant ~S cannot be a macro binding variable" variable)))

(defun source-check-macro-pattern (pattern)
  ;; NIL is a valid empty destructuring pattern, rather than a variable.
  (cond ((null pattern) nil)
        ((consp pattern) (source-check-macro-variables pattern))
        (t (source-check-macro-variable pattern))))

(defun source-check-macro-supplied-variable (specifier)
  (when (and (consp specifier) (consp (cddr specifier)))
    (source-check-macro-variable (third specifier))))

(defun source-check-macro-optional-variable (specifier)
  (source-check-macro-pattern (if (consp specifier) (first specifier) specifier))
  (source-check-macro-supplied-variable specifier))

(defun source-check-macro-key-variable (specifier)
  (let ((head (if (consp specifier) (first specifier) specifier)))
    ;; In ((keyword pattern) init supplied-p), the keyword is a name.
    (source-check-macro-pattern (if (consp head) (second head) head)))
  (source-check-macro-supplied-variable specifier))

(defun source-check-macro-variables (lambda-list)
  (let ((mode :required)
        (single-variable-p nil)
        (tail lambda-list))
    (loop while (consp tail)
          for item = (pop tail)
          do (cond
               (single-variable-p
                (source-check-macro-variable item)
                (setf single-variable-p nil))
               ((member item '(&whole &environment &rest &body))
                (setf single-variable-p t))
               ((eq item '&optional) (setf mode :optional))
               ((eq item '&key) (setf mode :key))
               ((eq item '&aux) (setf mode :aux))
               ((eq item '&allow-other-keys) nil)
               ((eq mode :optional) (source-check-macro-optional-variable item))
               ((eq mode :key) (source-check-macro-key-variable item))
               ((eq mode :aux)
                (source-check-macro-variable (if (consp item) (first item) item)))
               (t (source-check-macro-pattern item))))
    (when tail (source-check-macro-variable tail))))
