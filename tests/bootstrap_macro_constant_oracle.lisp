(let ((names (sort (loop for symbol being the external-symbols of :cl
                         when (constantp symbol)
                           collect (symbol-name symbol))
                   #'string<)))
  (dolist (name names)
    (write-line name)))
