(load (merge-pathnames "../src/load.lisp" *load-truename*))

(let ((arguments (cdr sb-ext:*posix-argv*)))
  (unless (= (length arguments) 2)
    (error "expected source and output paths"))
  (let ((unit (psl.compiler:read-unit (first arguments))))
    (unwind-protect
         (let ((compilation
                 (psl.compiler:analyze-unit
                  unit :target "x86_64-linux-gnu"
                       :profile "freestanding")))
           (psl.compiler:lower-unit compilation)
           (psl.compiler:optimize-unit compilation)
           (psl.compiler:linearize-unit compilation)
           (psl.compiler:emit-unit compilation (second arguments)))
      (psl.compiler:dispose-unit unit))))
