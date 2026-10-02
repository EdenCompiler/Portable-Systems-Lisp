;; Independent reader observations from the actual Stage 0 build host.
(load "src/package.lisp")
(let* ((unit (make-package "PSL.ENVIRONMENT.ORACLE" :use '("CL")))
       (*package* unit)
       (ids (make-hash-table :test #'eq))
       (next-id 0)
       (cases '("car" "CAR" "cl:car" "COMMON-LISP:CAR" "cl::car" "cl:|CAR|"
                "psl::car" "|car|" "\\c\\a\\r" "a|Bc|d" "name\\:colon"
                "|name with spaces:colon|" "||" ":||" ":hello" ":HELLO"
                "#:car" "#:car" "#:" "#:||" "load" "cl:load" "psl:load"
                "export" "psl:export" "wrap+" "psl:wrap+" "ffi:call"
                "psl.ffi:call" "cl::new-internal" "new-internal"
                "cl:new-internal" "missing:foo" "|cl|:car" "cl:" "cl::"
                ":" "::foo" "cl:::car" "a:b:c" "|bad" "bad\\" "#::car")))
  (do-external-symbols (symbol :psl)
    (unless (find-symbol (symbol-name symbol) :cl) (shadowing-import symbol unit)))
  ;; Deterministic generated case/escape combinations, all of which read as symbols.
  (dotimes (i 256)
    (let ((name (format nil "Name~D:with|escape\\end" i)))
      (push (with-output-to-string (stream)
              (write-char #\| stream)
              (loop for ch across name do
                (when (find ch "|\\") (write-char #\\ stream))
                (write-char ch stream))
              (write-char #\| stream)) cases)
      (push (format nil "mixed~D|Case|tail" i) cases)
      (push (format nil "MIXED~D|Case|TAIL" i) cases)))
  (with-open-file (stream (second sb-ext:*posix-argv*)
                          :direction :output :if-exists :supersede)
    (dolist (text cases)
      (handler-case
          (let* ((symbol (sb-ext:without-package-locks (read-from-string text)))
                 (home (symbol-package symbol))
                 (id (or (gethash symbol ids)
                         (setf (gethash symbol ids) (incf next-id)))))
            (assert (symbolp symbol))
            (format stream "~D~C~A~C~A~C~A~%" id #\Tab
                    (cond ((null home) "NONE") ((eq home unit) "SOURCE")
                          (t (package-name home)))
                    #\Tab (symbol-name symbol) #\Tab text))
        ((or reader-error end-of-file) () (format stream "0~CERROR~C~C~A~%" #\Tab #\Tab #\Tab text)))))
  (delete-package unit))
