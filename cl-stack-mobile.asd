(defsystem "cl-stack-mobile"
  :version "0.1.0"
  :description "cl-stack mobile toolchain: pinned cross ECL (android / ios-sim / wasm), mobile subset manifest, static-FFI path"
  :author "egao1980"
  :license "MIT"
  :depends-on ()
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "manifest"))
  :in-order-to ((test-op (test-op "cl-stack-mobile/tests"))))

(defsystem "cl-stack-mobile/tests"
  :depends-on ("cl-stack-mobile" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "manifest-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
