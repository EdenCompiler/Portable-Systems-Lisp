(in-package #:psl.frontend)

;; Source symbols stay distinct until lowering. Per-unit maps turn lexical
;; identities into deterministic string keys for the existing HIR/SSA interface;
;; linker names continue to use their separately validated C spelling.
(defvar *source-symbol-signatures* nil)
(defvar *lexical-symbol-names* nil)
(defvar *lexical-name-spellings* nil)
(defvar *lexical-name-counter* 0)

(defun lexical-name (symbol)
  (unless (and (symbolp symbol) (not (keywordp symbol))
               (not (member symbol '(nil t))))
    (fail "invalid lexical variable ~S" symbol))
  (if (null *lexical-symbol-names*) (source-name symbol)
      (or (gethash symbol *lexical-symbol-names*)
          (let* ((base (if (symbol-package symbol) (source-name symbol) "#:temporary"))
                 (name base))
            (loop while (gethash name *lexical-name-spellings*)
                  do (setf name (format nil "~A#~D" base (incf *lexical-name-counter*))))
            (setf (gethash name *lexical-name-spellings*) t
                  (gethash symbol *lexical-symbol-names*) name)))))

(defun source-function-signature (symbol context)
  (when (symbolp symbol)
    (let ((signature (gethash (source-name symbol) (analysis-context-signatures context))))
      (if *source-symbol-signatures*
          (or (gethash symbol *source-symbol-signatures*)
              (and signature (signature-external-p signature) signature))
          signature))))
