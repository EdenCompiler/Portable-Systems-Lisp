(in-package #:psl.ir)

(defun valid-type-p (type)
  (or (integer-type-p type) (float-type-p type) (eq type :void)
      (eq type :value)
      (eq type :boolean)
      (and (consp type) (eq (first type) :struct)
           (= (length type) 2) (stringp (second type)))
      (and (pointer-type-p type) (= (length type) 4)
           (valid-type-p (second type))
           (member (third type) '(t nil))
           (member (fourth type) '(t nil)))))

(defun integer-fits-p (value type pointer-bits)
  (let ((width (type-width type pointer-bits)))
    (and width (integerp value)
         (if (signed-type-p type)
             (<= (- (ash 1 (1- width))) value
                 (1- (ash 1 (1- width))))
             (<= 0 value (1- (ash 1 width)))))))

(defun literal-fits-p (value type pointer-bits)
  (cond ((eq type :f32) (typep value 'single-float))
        ((eq type :f64) (typep value 'double-float))
        ((eq type :boolean) (member value '(0 1)))
        ((eq type :value) (and (integerp value) (<= 0 value)
                               (< value (ash 1 64))))
        (t (integer-fits-p value type pointer-bits))))

(defun expect-count (items count description)
  (unless (and (listp items) (= (length items) count))
    (fail "invalid ~A: expected ~D operands" description count)))

(defun expect-same-type (actual expected description)
  (unless (equal actual expected)
    (fail "~A type mismatch: expected ~S, got ~S"
          description expected actual)))
