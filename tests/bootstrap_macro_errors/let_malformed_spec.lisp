(defmacro malformed_let () (let ((x '1 '2)) x))
(malformed_let)
