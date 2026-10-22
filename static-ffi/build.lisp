;;;; Static-FFI spike driver. Run with the host ECL (out/host/bin/ecl):
;;;;
;;;;   ecl --norc --load static-ffi/build.lisp
;;;;
;;;; Loads CFFI on the host, then compiles CFFI's whole dependency closure plus
;;;; the spike for the target (COMPILE-FILE :TARGET, :SYSTEM-P T) with the
;;;; :CFFI-STATIC-LINK feature, and links one executable against the target's
;;;; static libecl.a and the native archives. No shared object is opened at run
;;;; time. Env (all required unless noted):
;;;;   CSM_TARGET_INFO   target-info.lisp of the static ECL build
;;;;   CSM_LISP_DIRS     colon-separated ASDF trees holding cffi (patched),
;;;;                     alexandria, babel, trivial-features
;;;;   CSM_NATIVE_LIBS   space-separated archives / link flags (libsqlite3.a libuv.a …)
;;;;   CSM_GROVEL_FLAGS  C flags for the host grovel run (-I for uv.h)
;;;;   CSM_GROVEL_OUTPUT optional: reuse this processed grovel file instead of grovelling
;;;;   CSM_OUTPUT        executable path
;;;;   CSM_WORK          scratch dir for objects

(setf *debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (format *error-output* "~&static-ffi build: ~a~%" c)
        (ext:quit 1)))

(require :asdf)

(defun env (name &optional (required t))
  (let ((v (ext:getenv name)))
    (cond ((and v (plusp (length v))) v)
          (required (error "~a is required" name)))))

(defun split (string char)
  (loop for start = 0 then (1+ end)
        for end = (position char string :start start)
        for part = (subseq string start end)
        when (plusp (length part)) collect part
        while end))

(defvar *here* (make-pathname :name nil :type nil :defaults *load-truename*))
(defvar *work* (uiop:ensure-directory-pathname (env "CSM_WORK")))

(asdf:initialize-source-registry
 `(:source-registry
   ,@(mapcar (lambda (d) `(:tree ,d)) (split (env "CSM_LISP_DIRS") #\:))
   :ignore-inherited-configuration))

(asdf:load-system "cffi")
(asdf:load-system "cffi-grovel")
(format t "~&; host cffi ~a, ecl method ~s~%"
        (asdf:component-pathname (asdf:find-system "cffi"))
        (symbol-value (find-symbol "*CFFI-ECL-METHOD*" "CFFI-SYS")))

(defun closure-source-files (system)
  "CL source files of SYSTEM and its dependencies in load order, minus what
the image already provides (ASDF/UIOP come from the prebuilt libasdf.a)."
  (remove-if (lambda (c)
               (or (not (typep c 'asdf:cl-source-file))
                   (member (asdf:component-name (asdf:component-system c))
                           '("asdf" "uiop") :test #'string=)))
             (asdf:required-components system
                                       :other-systems t :force :all
                                       :component-type 'asdf:cl-source-file
                                       :goal-operation 'asdf:load-op
                                       :keep-operation 'asdf:load-op)))

(defun trivial-features-for (features)
  "What trivial-features' tf-ecl.lisp pushes when loaded on the target. The
host pushed its own at load time; target-info only has ECL's base set."
  (flet ((has (&rest fs) (some (lambda (f) (member f features)) fs)))
    (remove nil
            (list (when (has :darwin) :unix)
                  (when (has :win32) :windows)
                  (when (has :x86_64) :x86-64)
                  (when (has :i386 :i486 :i586 :i686) :x86)
                  (when (has :armv5l :armv6l :armv7l) :arm)
                  (when (has :aarch64 :armv8l :armv8b :aarch64_be) :arm64)
                  (when (has :uint64-t) :64-bit)
                  (when (and (has :uint32-t) (not (has :uint64-t))) :32-bit)))))

(defun object-path (file tag)
  ;; ECL derives a file's init symbol from the object's name, so two
  ;; package.o in one program collide at link time.
  (merge-pathnames (make-pathname :directory '(:relative "obj")
                                  :name (format nil "~a--~a" tag (pathname-name file))
                                  :type "o")
                   *work*))

(let* ((target (c::read-target-info (env "CSM_TARGET_INFO")))
       (features (find '*features* target :key #'car))
       (grovel-out (or (env "CSM_GROVEL_OUTPUT" nil)
                       (merge-pathnames "uv-grovel-processed.lisp" *work*)))
       (objects '()))
  (dolist (f (cons :cffi-static-link (trivial-features-for (cdr features))))
    (pushnew f (cdr features)))
  (format t "~&; target features ~s~%" (cdr features))
  (ensure-directories-exist *work*)
  (load (merge-pathnames "package.lisp" *here*))
  (unless (env "CSM_GROVEL_OUTPUT" nil)
    (let ((cffi-grovel::*cc-flags*
            (append (split (env "CSM_GROVEL_FLAGS") #\Space)
                    (symbol-value 'cffi-grovel::*cc-flags*))))
      (format t "~&; grovel ~a~%" grovel-out)
      (setf grovel-out
            (cffi-grovel:process-grovel-file (merge-pathnames "uv-grovel.lisp" *here*) grovel-out))))
  (flet ((compile-for-target (source tag)
           (let ((out (object-path source tag)))
             (ensure-directories-exist out)
             (format t "~&; target compile ~a~%" (enough-namestring source))
             (multiple-value-bind (fasl warnings-p failure-p)
                 (compile-file source :output-file out :system-p t :target target)
               (declare (ignore warnings-p))
               (when (or (null fasl) failure-p)
                 (error "compile failed: ~a" source))
               (push fasl objects)))))
    (dolist (c (closure-source-files "cffi"))
      (compile-for-target (asdf:component-pathname c)
                          (format nil "~{~a~^-~}" (butlast (asdf:component-find-path c)))))
    (compile-for-target (merge-pathnames "package.lisp" *here*) "spike")
    (compile-for-target grovel-out "spike")
    (compile-for-target (merge-pathnames "spike.lisp" *here*) "spike"))
  (let ((libasdf (merge-pathnames "libasdf.a" (cdr (find 'c::*ecl-library-directory* target :key #'car))))
        (output (env "CSM_OUTPUT")))
    (unless (probe-file libasdf)
      (setf libasdf (first (directory (merge-pathnames "*/libasdf.a" (cdr (find 'c::*ecl-library-directory* target :key #'car)))))))
    (format t "~&; link ~a (~d objects + ~a)~%" output (length objects) libasdf)
    (with-compilation-unit (:target target)
      (c:build-program output
                       :lisp-files (cons libasdf (reverse objects))
                       :ld-flags (split (env "CSM_NATIVE_LIBS") #\Space)
                       :epilogue-code '(handler-case
                                        (progn (funcall (intern "MAIN" "STATIC-FFI-SPIKE"))
                                               (ext:quit 0))
                                      (error (e)
                                        (format *error-output* "~&static-ffi: ~a~%" e)
                                        (ext:quit 1)))))
    (format t "~&; built ~a~%" output)))

(ext:quit 0)
