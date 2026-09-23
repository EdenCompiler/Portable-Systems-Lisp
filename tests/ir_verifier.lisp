(load (merge-pathnames "../src/load.lisp" *load-truename*))

(defun expect-failure (label operation expected)
  (let ((condition (handler-case (progn (funcall operation) nil)
                     (error (error) error))))
    (unless condition
      (error "~A unexpectedly passed verification" label))
    (unless (search expected (princ-to-string condition))
      (error "~A failed for the wrong reason: ~A" label condition))))

(let* ((signature (psl.ir:make-signature
                   :name "bad" :arguments nil :result :u64
                   :external-p nil))
       (signatures (make-hash-table :test #'equal)))
  (setf (gethash "bad" signatures) signature)

  (expect-failure
   "HIR literal"
   (lambda ()
     (psl.ir:verify-hir-function
      (psl.ir:make-function-def
       :signature signature :parameters nil
       :body (psl.ir:make-hir :kind :literal :type :u64
                              :value -1 :children nil))
      signatures 64))
   "does not fit")

  (let* ((entry (psl.ir:make-ssa-block
                 :id 0
                 :instructions (list (psl.ir:make-ssa-instruction
                                      :id 0 :op :constant :type :boolean
                                      :value 1))
                 :terminator (psl.ir:make-ssa-terminator
                              :op :branch :args '(0) :targets '(1 2))))
         (left (psl.ir:make-ssa-block
                :id 1
                :instructions (list (psl.ir:make-ssa-instruction
                                     :id 1 :op :constant :type :u64 :value 1))
                :terminator (psl.ir:make-ssa-terminator
                             :op :jump :targets '(3))))
         (right (psl.ir:make-ssa-block
                 :id 2
                 :instructions (list (psl.ir:make-ssa-instruction
                                      :id 2 :op :constant :type :u64 :value 2))
                 :terminator (psl.ir:make-ssa-terminator
                              :op :jump :targets '(3))))
         (join (psl.ir:make-ssa-block
                :id 3
                :instructions (list (psl.ir:make-ssa-instruction
                                     :id 3 :op :phi :type :u64
                                     :args '((1 . 1))))
                :terminator (psl.ir:make-ssa-terminator
                             :op :return :args '(3))))
         (function (psl.ir:make-ssa-function
                    :name "bad" :signature signature :entry 0
                    :blocks (list entry left right join) :next-value 4)))
    (expect-failure
     "SSA join"
     (lambda () (psl.ir:verify-ssa-function function signatures 64))
     "phi inputs do not match predecessors")
    (setf (psl.ir:ssa-block-instructions join) nil
          (psl.ir:ssa-terminator-args
           (psl.ir:ssa-block-terminator join)) '(1))
    (expect-failure
     "SSA dominance"
     (lambda () (psl.ir:verify-ssa-function function signatures 64))
     "does not dominate its use"))

  (expect-failure
   "LIR target"
   (lambda ()
     (psl.ir:verify-lir-function
      (psl.ir:make-lir-function
       :name "bad" :signature signature :register-count 1
       :instructions
       (list (psl.ir:make-lir-instruction :op :label :value 0)
             (psl.ir:make-lir-instruction
              :op :constant :dst 0 :type :u64 :value '(42 . :u64))
             (psl.ir:make-lir-instruction :op :jump :value 9)))
      signatures 64))
   "undefined label")

  (expect-failure
   "LIR fallthrough"
   (lambda ()
     (psl.ir:verify-lir-function
      (psl.ir:make-lir-function
       :name "bad" :signature signature :register-count 1
       :instructions
       (list (psl.ir:make-lir-instruction :op :label :value 0)
             (psl.ir:make-lir-instruction
              :op :constant :dst 0 :type :u64 :value '(42 . :u64))))
      signatures 64))
   "without a return")

  (expect-failure
   "LIR definite assignment"
   (lambda ()
     (psl.ir:verify-lir-function
      (psl.ir:make-lir-function
       :name "bad" :signature signature :register-count 2
       :instructions
       (list (psl.ir:make-lir-instruction :op :label :value 0)
             (psl.ir:make-lir-instruction
              :op :constant :dst 0 :type :boolean :value '(1 . :boolean))
             (psl.ir:make-lir-instruction
              :op :branch-zero :value 2 :args '(0))
             (psl.ir:make-lir-instruction :op :label :value 1)
             (psl.ir:make-lir-instruction
              :op :constant :dst 1 :type :u64 :value '(42 . :u64))
             (psl.ir:make-lir-instruction :op :jump :value 3)
             (psl.ir:make-lir-instruction :op :label :value 2)
             (psl.ir:make-lir-instruction :op :jump :value 3)
             (psl.ir:make-lir-instruction :op :label :value 3)
             (psl.ir:make-lir-instruction
              :op :return :type :u64 :args '(1))))
      signatures 64))
   "may be used before assignment"))

(let ((unit (psl.compiler:read-unit
             (merge-pathnames "../examples/standalone.lisp"
                              *load-truename*))))
  (unwind-protect
       (let ((compilation (psl.compiler:analyze-unit unit)))
         (psl.compiler:lower-unit compilation)
         (psl.compiler:linearize-unit compilation)
         (let* ((function (first (psl.compiler:compilation-lir-functions
                                  compilation)))
                (return (find :return
                              (psl.ir:lir-function-instructions function)
                              :key #'psl.ir:lir-instruction-op)))
           (setf (psl.ir:lir-instruction-args return) '(999))
           (expect-failure
            "pre-emission LIR verification"
            (lambda () (psl.compiler:emit-unit compilation "/dev/null"))
            "undefined register")))
    (psl.compiler:dispose-unit unit)))

(format t "PSL IR verifier tests passed~%")
