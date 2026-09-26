(defun weighted_eight (a b c d e f g h)
  (declare (type u64 a b c d e f g h) (returns u64) (c-export :c))
  (wrap+ a
    (wrap+ (wrap* b 10)
      (wrap+ (wrap* c 100)
        (wrap+ (wrap* d 1000)
          (wrap+ (wrap* e 10000)
            (wrap+ (wrap* f 100000)
              (wrap+ (wrap* g 1000000) (wrap* h 10000000)))))))))

(defun seventh_argument (a b c d e f g)
  (declare (type u64 a b c d e f g) (returns u64) (c-export :c))
  g)

(defun mixed_stack (a b c d e f g h i)
  (declare (type u64 a b c d e f) (type s8 g) (type u16 h)
           (type (ptr s32) i) (returns s64) (c-export :c))
  (wrap+ (wrap-cast s64 g)
    (wrap+ (wrap-cast s64 h) (wrap-cast s64 (deref i)))))

(defun next_argument (counter)
  (declare (type (ptr u64) counter) (returns u64))
  (store counter (wrap+ (deref counter) 1)))

(defun ordered_eight (counter)
  (declare (type (ptr u64) counter) (returns u64) (c-export :c))
  (weighted_eight (next_argument counter) (next_argument counter)
                  (next_argument counter) (next_argument counter)
                  (next_argument counter) (next_argument counter)
                  (next_argument counter) (next_argument counter)))

(defun nested_stack ()
  (declare (returns u64) (c-export :c))
  (weighted_eight 1 2 3 4 5 6
    (seventh_argument 0 0 0 0 0 0 7)
    (seventh_argument 0 0 0 0 0 0
      (seventh_argument 0 0 0 0 0 0 8))))

(defun call_mixed_stack (pointer)
  (declare (type (ptr s32) pointer) (returns s64) (c-export :c))
  (mixed_stack 1 2 3 4 5 6 -128 65535 pointer))

(defun recursive_eight (n b c d e f g h)
  (declare (type u64 n b c d e f g h) (returns u64) (c-export :c))
  (if (= n 0)
      (weighted_eight 1 b c d e f g h)
      (recursive_eight (wrap- n 1) b c d e f g h)))
