;; Bounded, NUL-aware option matching. Source/output remain two positional
;; paths; the complete Stage 0 CLI is a separate remaining driver port.
(defun compiler_text_matches (text bits remaining)
  (declare (type (ptr u8) text) (type u64 bits) (type usize remaining) (returns c-int))
  (if (= remaining 0) 1
      (if (= (ptr-address text) 0) 0
          (if (= (deref text) 0) 0
              (if (= (deref text) (wrap-cast u8 bits))
                  (compiler_text_matches (pointer+ text 1) (shr64 bits 8) (wrap- remaining 1)) 0)))))

;; Target suffixes use two eight-byte chunks and a short tail.
(defun compiler_target_suffix_p (text first second tail size)
  (declare (type (ptr u8) text) (type u64 first second tail) (type usize size) (returns c-int))
  (if (= (compiler_text_matches text first 8) 1)
      (if (= (compiler_text_matches (pointer+ text 8) second 8) 1)
          (if (= (compiler_text_matches (pointer+ text 16) tail size) 1)
              (if (= (deref (pointer+ text (wrap-cast isize (wrap+ 16 size)))) 0) 1 0) 0) 0) 0))

(defun compiler_parse_target_tail (text)
  (declare (type (ptr u8) text) (returns c-int))
  (cond
    ;; "=x86_64-", "linux-gn", "u"
    ((= (compiler_target_suffix_p text #x2d34365f3638783d #x6e672d78756e696c #x75 1) 1) 0)
    ;; "=aarch64", "-linux-g", "nu"
    ((= (compiler_target_suffix_p text #x343668637261613d #x672d78756e696c2d #x756e 2) 1) 1)
    ;; "=riscv64", "-linux-g", "nu"
    ((= (compiler_target_suffix_p text #x343676637369723d #x672d78756e696c2d #x756e 2) 1) 2)
    ;; "=x86_64-", "windows-", "gnu"
    ((= (compiler_target_suffix_p text #x2d34365f3638783d #x2d73776f646e6977 #x756e67 3) 1) 3)
    (t -1)))

;; The prefix chunk spells "--target".
(defun compiler_parse_target (text)
  (declare (type (ptr u8) text) (returns c-int))
  (if (= (compiler_text_matches text #x7465677261742d2d 8) 1)
      (compiler_parse_target_tail (pointer+ text 8)) -1))

(defun compiler_run_parsed_options (argv optimization target)
  (declare (type (ptr (ptr u8)) argv) (type c-int optimization target) (returns c-int))
  (if (if (< optimization 0) t (< target 0))
      (compiler_path_error 5 (ptr-from-address (ptr u8) 0))
      (native_run_compiler_target (deref (pointer+ argv 3)) (deref (pointer+ argv 4))
                                  (wrap-cast u32 optimization) (wrap-cast u32 target))))

(defun compiler_main_two_options (argv)
  (declare (type (ptr (ptr u8)) argv) (returns c-int))
  (let ((first (deref (pointer+ argv 1))) (second (deref (pointer+ argv 2))))
    (let ((optimization (compiler_parse_optimization first)) (target (compiler_parse_target second)))
      (if (if (< optimization 0) t (< target 0))
          (compiler_run_parsed_options argv (compiler_parse_optimization second) (compiler_parse_target first))
          (compiler_run_parsed_options argv optimization target)))))
