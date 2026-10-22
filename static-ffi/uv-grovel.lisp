;;;; cffi-grovel spec. build.lisp processes it on the host once; the processed
;;;; file is what gets compiled for the target (no grovel run on device).
(in-package #:static-ffi-spike)

(include "uv.h")

(constant (+uv-version-major+ "UV_VERSION_MAJOR"))
(constant (+uv-version-minor+ "UV_VERSION_MINOR"))
