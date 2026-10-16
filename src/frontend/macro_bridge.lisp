(in-package #:psl.frontend)

(defun source-explicit-nil-key-spec-p (specifier)
  (and (consp specifier)
       (consp (first specifier))
       (null (first (first specifier)))))

(defun source-nil-key-lambda-list-p (lambda-list)
  (when (or (null lambda-list) (ignore-errors (list-length lambda-list)))
    (loop with in-keys = nil
          for item in lambda-list
          do (cond
               ((eq item '&key) (setf in-keys t))
               ((member item '(&allow-other-keys &aux)) (return nil))
               ((eq item '&environment) nil)
               (in-keys
                (when (source-explicit-nil-key-spec-p item)
                  (return-from source-nil-key-lambda-list-p t)))))))

(defun source-bridge-nil-key-lambda-list (lambda-list)
  (let* ((key-position (position '&key lambda-list))
         (aux-position (position '&aux lambda-list))
         (key-end (or aux-position (length lambda-list))))
    (unless key-position
      (return-from source-bridge-nil-key-lambda-list lambda-list))
    (when (member '&allow-other-keys
                  (subseq lambda-list key-position key-end))
      (return-from source-bridge-nil-key-lambda-list lambda-list))
    (append (subseq lambda-list 0 key-end)
            (list '&allow-other-keys)
            (subseq lambda-list key-end))))

(defun source-eval-macro-definition (form)
  (let* ((name (second form))
         (lambda-list (third form))
         (nil-key-p (source-nil-key-lambda-list-p lambda-list))
         (definition (if nil-key-p
                         (append (subseq form 0 2)
                                 (list (source-bridge-nil-key-lambda-list lambda-list))
                                 (subseq form 3))
                         form)))
    (prog1 (eval definition)
      (when nil-key-p
        (let ((expander (macro-function name)))
          (setf (macro-function name)
                (lambda (invocation environment)
                  (source-check-nil-key-arguments lambda-list (rest invocation))
                  (funcall expander invocation environment))))))))

(defun source-macro-key-variable (specifier)
  (let ((head (if (consp specifier) (first specifier) specifier)))
    (if (consp head) (second head) head)))

(defun source-macro-key-name-matches-p (argument specifier)
  (let ((head (if (consp specifier) (first specifier) specifier)))
    (if (consp head)
        (eq argument (first head))
        (and (symbolp argument)
             (eq (symbol-package argument) (find-package :keyword))
             (string= (symbol-name argument)
                      (symbol-name (source-macro-key-variable specifier)))))))

(defun source-macro-key-layout (lambda-list)
  (let ((required 0)
        (optional 0)
        (optional-p nil)
        (tail lambda-list)
        (key-specifiers nil)
        (allow-other-keys-p nil))
    (loop while tail
          for item = (pop tail)
          do (cond
               ((eq item '&key)
                (loop while tail
                      for specifier = (first tail)
                      do (cond
                           ((eq specifier '&allow-other-keys)
                            (setf allow-other-keys-p t)
                            (pop tail)
                            (return))
                           ((eq specifier '&aux) (return))
                           ((eq specifier '&environment)
                            (pop tail)
                            (pop tail))
                           (t (push (pop tail) key-specifiers))))
                (setf key-specifiers (nreverse key-specifiers))
                (return))
               ((member item '(&whole &environment)) (pop tail))
               ((eq item '&optional) (setf optional-p t))
               ((member item '(&rest &body)) (pop tail))
               ((eq item '&aux) (return))
               (optional-p (incf optional))
               (t (incf required))))
    (values required optional key-specifiers allow-other-keys-p)))

(defun source-macro-key-arguments (lambda-list arguments)
  (multiple-value-bind (required optional key-specifiers allow-other-keys-p)
      (source-macro-key-layout lambda-list)
    (if (or (null (position '&key lambda-list))
            (< (length arguments) required))
        (values nil key-specifiers allow-other-keys-p)
        (let* ((optional-supplied (min optional (- (length arguments) required)))
               (position (+ required optional-supplied)))
          (values (nthcdr position arguments) key-specifiers allow-other-keys-p)))))

(defun source-macro-key-known-p (key key-specifiers)
  (or (eq key :allow-other-keys)
      (some (lambda (specifier)
              (source-macro-key-name-matches-p key specifier))
            key-specifiers)))

(defun source-macro-key-allow-value (arguments)
  (loop for (key value) on arguments by #'cddr
        when (eq key :allow-other-keys)
          do (return value)))

(defun source-check-nil-key-arguments (lambda-list arguments)
  (multiple-value-bind (key-arguments key-specifiers allow-other-keys-p)
      (source-macro-key-arguments lambda-list arguments)
    (when (or allow-other-keys-p (null key-arguments)
              (oddp (length key-arguments))
              (source-macro-key-allow-value key-arguments))
      (return-from source-check-nil-key-arguments t))
    (loop for key in key-arguments by #'cddr
          unless (source-macro-key-known-p key key-specifiers)
            do (error "unknown keyword argument ~S" key))
    t))
