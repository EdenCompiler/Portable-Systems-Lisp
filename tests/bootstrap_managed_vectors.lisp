(defun vector_round_trip (initial item)
  (declare (type value initial item)
           (returns u64)
           (c-export :c))
  (let ((vector (make-value-vector 2 initial)))
    (let ((index (value-vector-push vector item)))
      (if (= index 2)
          (if (eq (value-vector-ref vector 0) initial)
              (if (eq (value-vector-set vector 1 item) item)
                  (if (= (value-vector-length vector) 3) 0 3)
                  2)
              1)
          4))))

(defun vector_noalloc_read (vector index expected)
  (declare (type value vector expected)
           (type usize index)
           (returns u64)
           (c-export :c))
  (without-allocation
    (if (eq (value-vector-ref vector index) expected)
        (if (= (value-vector-length vector) 3) 0 1)
        2)))

(defun vector_noalloc_set (vector index item)
  (declare (type value vector item)
           (type usize index)
           (returns value)
           (c-export :c))
  (without-allocation
    (value-vector-set vector index item)))

(defun vector_fill (vector count)
  (declare (type value vector) (type s64 count) (returns value))
  (if (= count 0)
      vector
      (progn
        (value-vector-push vector (cons (box-fixnum count) nil))
        (vector_fill vector (wrap- count 1)))))

(defun vector_build (count)
  (declare (type s64 count) (returns value) (c-export :c))
  (vector_fill (make-value-vector 0 nil) count))
