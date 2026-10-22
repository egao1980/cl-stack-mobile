;;;; Ordinary CFFI client code, unchanged from a dlopen build: compiled with
;;;; the :CFFI-STATIC-LINK feature, DEFCFUN becomes an FFI:C-INLINE call to an
;;;; extern resolved by the linker and USE-FOREIGN-LIBRARY opens nothing.
(in-package #:static-ffi-spike)

(cffi:define-foreign-library libsqlite3
  (t (:default "libsqlite3")))
(cffi:use-foreign-library libsqlite3)

(cffi:define-foreign-library libuv
  (t (:default "libuv")))
(cffi:use-foreign-library libuv)

(cffi:defcfun ("sqlite3_libversion" sqlite3-libversion) :string)
(cffi:defcfun ("uv_version_string" uv-version-string) :string)

(defun load-state (name)
  (cffi:foreign-library-load-state
   (find name (cffi:list-foreign-libraries :loaded-only nil) :key #'cffi:foreign-library-name)))

(defun main ()
  (let ((sqlite (sqlite3-libversion))
        (uv (uv-version-string))
        (grovel (format nil "~d.~d." +uv-version-major+ +uv-version-minor+)))
    (format t "static-ffi: ~a ~a~%" (lisp-implementation-type) (lisp-implementation-version))
    (format t "static-ffi: libsqlite3 ~(~a~), libuv ~(~a~), linked ~s~%"
            (load-state 'libsqlite3)
            (load-state 'libuv)
            cffi:*foreign-libraries-linked*)
    (format t "static-ffi: sqlite3_libversion() = ~a~%" sqlite)
    (format t "static-ffi: uv_version_string() = ~a (grovel ~a)~%" uv grovel)
    (finish-output)
    (unless (and (eq :static (load-state 'libuv))
                 (eq 0 (search grovel uv)))
      (error "static-ffi: unexpected state"))))
