;; Shared matching for inline optimization, target, and profile options.
(defun compiler_parse_profile (text)
  (declare (type (ptr u8) text) (returns c-int))
  (if (= (compiler_text_matches text #x6c69666f72702d2d 8) 0) -1
      (if (= (compiler_text_matches (pointer+ text 8) #x3d65 2) 0) -1
          (cond
            ((= (compiler_text_matches (pointer+ text 10) #x646574736f68 6) 1)
             (if (= (deref (pointer+ text 16)) 0) 1 -1))
            ((= (compiler_text_matches (pointer+ text 10) #x6e61747365657266 8) 1)
             (if (= (compiler_text_matches (pointer+ text 18) #x676e6964 4) 1)
                 (if (= (deref (pointer+ text 22)) 0) 0 -1) -1))
            (t -1)))))

(defun compiler_option_kind (text)
  (declare (type (ptr u8) text) (returns u32))
  (if (= (ptr-address text) 0) 0
      (if (< (compiler_parse_optimization text) 0)
          (if (< (compiler_parse_target text) 0)
              (if (< (compiler_parse_profile text) 0) (wrap-cast u32 0) (wrap-cast u32 4))
              (wrap-cast u32 2)) (wrap-cast u32 1))))

(defun compiler_option_value (text kind)
  (declare (type (ptr u8) text) (type u32 kind) (returns u32))
  (wrap-cast u32
   (cond ((= kind 1) (compiler_parse_optimization text))
         ((= kind 2) (compiler_parse_target text))
         (t (compiler_parse_profile text)))))
