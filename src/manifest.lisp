(in-package #:cl-stack-mobile)

(defun %root-file (name)
  (asdf:system-relative-pathname "cl-stack-mobile" name))

(defun ecl-pin ()
  "Plist of the KEY=VALUE pairs in ecl.pin (keys as keywords, values as strings)."
  (with-open-file (in (%root-file "ecl.pin"))
    (loop for line = (read-line in nil)
          while line
          for trimmed = (string-trim '(#\Space #\Tab #\Return) line)
          for eq = (position #\= trimmed)
          when (and eq (plusp (length trimmed)) (char/= (char trimmed 0) #\#))
            append (list (intern (substitute #\- #\_ (subseq trimmed 0 eq)) :keyword)
                         (subseq trimmed (1+ eq))))))

(defun mobile-subset ()
  "Entries of pins/mobile.lisp: (system-keyword . plist)."
  (with-open-file (in (%root-file "pins/mobile.lisp"))
    (with-standard-io-syntax
      (let ((*read-eval* nil))
        (read in)))))

(defun subset-entry (system)
  (let ((key (intern (string-upcase (string system)) :keyword)))
    (find key (mobile-subset) :key #'first)))

(defun device-subset ()
  "Systems that ship in on-device images (entries without :device nil)."
  (loop for (system . plist) in (mobile-subset)
        unless (and (member :device plist) (null (getf plist :device)))
          collect system))
