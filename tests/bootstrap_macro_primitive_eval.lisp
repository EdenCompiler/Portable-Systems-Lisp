(defmacro primitive-values ()
  (if (and 0 37)
      (if (and nil (if nil 99 98))
          99
          (if (= -0 0)
              (if (= #x10 16)
                  (if (eq (second '(nil t)) t) 37 99)
                  99)
              99))
      99))

(defmacro primitive-equal-one () (if (= 42) 43 99))

(defmacro primitive-second-short ()
  (if (eq (second '(nil)) nil) 41 99))

(defmacro primitive-second-empty ()
  (if (eq (second nil) nil) 42 99))

(defmacro primitive-eq-empty-list-nil ()
  (if (eq (second '(x ())) nil) 46 99))

(defmacro primitive-eq-nil-empty-list ()
  (if (eq nil (second '(x ()))) 47 99))

(defmacro primitive-eq-quoted-empty-list ()
  (if (eq nil '()) 48 99))

(defmacro primitive-eq-distinct-symbols ()
  (if (eq 'left 'right) 99 49))

(defmacro primitive-eq-qualified-escaped-symbol ()
  (if (eq 'KEYWORD:|SAME+| 'KEYWORD:SAME+) 50 99))

(defmacro primitive-second-three ()
  (if (eq (second '(nil t nil)) t) 44 99))

(defmacro primitive-second-list ()
  (second '(99 (wrap+ 20 23))))

(defmacro primitive-length-zero () (length nil))
(defmacro primitive-length-two () (length '(a b)))
(defmacro primitive-length-ten () (length '(a b c d e f g h i j)))
(defmacro primitive-length-template ()
  `(if (= ,(length '(a b)) 2) 45 99))

(defun macro_primitive_values ()
  (declare (returns u64) (c-export :c))
  (primitive-values))

(defun macro_primitive_equal_one ()
  (declare (returns u64) (c-export :c))
  (primitive-equal-one))

(defun macro_primitive_second_short ()
  (declare (returns u64) (c-export :c))
  (primitive-second-short))

(defun macro_primitive_second_empty ()
  (declare (returns u64) (c-export :c))
  (primitive-second-empty))

(defun macro_primitive_eq_empty_list_nil ()
  (declare (returns u64) (c-export :c))
  (primitive-eq-empty-list-nil))

(defun macro_primitive_eq_nil_empty_list ()
  (declare (returns u64) (c-export :c))
  (primitive-eq-nil-empty-list))

(defun macro_primitive_eq_quoted_empty_list ()
  (declare (returns u64) (c-export :c))
  (primitive-eq-quoted-empty-list))

(defun macro_primitive_eq_distinct_symbols ()
  (declare (returns u64) (c-export :c))
  (primitive-eq-distinct-symbols))

(defun macro_primitive_eq_qualified_escaped_symbol ()
  (declare (returns u64) (c-export :c))
  (primitive-eq-qualified-escaped-symbol))

(defun macro_primitive_second_three ()
  (declare (returns u64) (c-export :c))
  (primitive-second-three))

(defun macro_primitive_second_list ()
  (declare (returns u64) (c-export :c))
  (primitive-second-list))

(defun macro_primitive_length_zero ()
  (declare (returns u64) (c-export :c))
  (primitive-length-zero))

(defun macro_primitive_length_two ()
  (declare (returns u64) (c-export :c))
  (primitive-length-two))

(defun macro_primitive_length_ten ()
  (declare (returns u64) (c-export :c))
  (primitive-length-ten))

(defun macro_primitive_length_template ()
  (declare (returns u64) (c-export :c))
  (primitive-length-template))
