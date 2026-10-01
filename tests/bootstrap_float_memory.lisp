(defcstruct float_record
  (single f32)
  (wide c-double))

(ffi:export-data "psl_single" c-float -0.0f0)
(ffi:export-data "psl_wide" f64 1.00000000000000033306690738754696212708950042724609375d0)
(ffi:export-data "psl_small" f64 4.9406564584124654417656879286822137236505980261432476442558568250067550727020875186529983636163599237979656469544571773092665671d-324)

(defun float_copy (destination source)
  (declare (type (ptr f32) destination source) (returns c-int) (c-export :c))
  (store destination (deref source))
  0)

(defun double_copy (destination source)
  (declare (type (ptr f64) destination source) (returns c-int) (c-export :c))
  (store destination (deref source))
  0)

(defun float_store (destination)
  (declare (type (ptr c-float) destination) (returns c-int) (c-export :c))
  (store destination 1.000000059604644775390625f0)
  0)

(defun double_store (destination)
  (declare (type (ptr c-double) destination) (returns c-int) (c-export :c))
  (store destination -0.0d0)
  0)

(defun float_field_store (record)
  (declare (type (ptr float_record) record) (returns c-int) (c-export :c))
  (store (field-pointer record 'single) .5f0)
  (store (field-pointer record 'wide) 3.25d0)
  0)

(defun float_truth (source)
  (declare (type (ptr f32) source) (returns c-int) (c-export :c))
  (if (deref source) 42 7))

(defun float_literal_truth ()
  (declare (returns c-int) (c-export :c))
  (if -0.0d0 42 7))

(defun float_branch_copy (destination yes no flag)
  (declare (type (ptr f64) destination yes no) (type u64 flag)
           (returns c-int) (c-export :c))
  (store destination (if (= flag 1) (deref yes) (deref no)))
  0)
