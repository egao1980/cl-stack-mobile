/* Minimal native shell: boot the linked ECL image, print the implementation
 * string, shut down. The same file is the wasm, Android and iOS-simulator
 * proof; the bridge frame (JSON over JNI / WKScriptMessageHandler) replaces
 * printf in P0 step 5. */
#include <stdio.h>
#include <ecl/ecl.h>

int main(int argc, char **argv) {
  cl_boot(argc, argv);
  cl_object form = c_string_to_object(
      "(format nil \"~A ~A on ~A ~A\" (lisp-implementation-type)"
      " (lisp-implementation-version) (software-type) (machine-type))");
  cl_object s = si_coerce_to_base_string(cl_eval(form));
  printf("hello-ecl: %s\n", ecl_base_string_pointer_safe(s));
  fflush(stdout);
  cl_shutdown();
  return 0;
}
