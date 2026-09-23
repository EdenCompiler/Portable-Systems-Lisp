(load (merge-pathnames "../src/load.lisp" *load-truename*))

(let ((arguments (cdr sb-ext:*posix-argv*)))
  (unless (= (length arguments) 2)
    (error "expected source and output paths"))
  (psl.compiler:compile-source (first arguments) (second arguments)
                               :target "x86_64-linux-gnu"
                               :profile "freestanding"))
