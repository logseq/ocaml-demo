#include "ocaml_demo_core_ffi.h"

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static pthread_mutex_t ocaml_demo_call_mutex = PTHREAD_MUTEX_INITIALIZER;
static int ocaml_demo_runtime_started = 0;
static char *ocaml_demo_response = NULL;

static void ensure_ocaml_runtime(void) {
  if (!ocaml_demo_runtime_started) {
    static char program_name[] = "ocaml_demo_mobile";
    char *argv[] = {program_name, NULL};
    caml_startup(argv);
    ocaml_demo_runtime_started = 1;
  }
}

static const char *replace_response(const char *value) {
  size_t length = strlen(value);
  char *copy = malloc(length + 1);
  if (copy == NULL) {
    return
      "{\"apiVersion\":1,\"ok\":false,\"result\":null,\"error\":{\"code\":"
      "\"allocation_failure\",\"message\":\"Could not allocate the RPC response\"}}";
  }
  memcpy(copy, value, length + 1);
  free(ocaml_demo_response);
  ocaml_demo_response = copy;
  return ocaml_demo_response;
}

const char *ocaml_demo_call(const char *request_json) {
  const char *response;
  pthread_mutex_lock(&ocaml_demo_call_mutex);
  ensure_ocaml_runtime();

  CAMLparam0();
  CAMLlocal2(request, result);
  const value *callback = caml_named_value("ocaml_demo_mobile_call");
  if (callback == NULL) {
    response = replace_response(
      "{\"apiVersion\":1,\"ok\":false,\"result\":null,\"error\":{\"code\":"
      "\"missing_callback\",\"message\":\"OCaml RPC callback is not registered\"}}");
  } else {
    request = caml_copy_string(request_json == NULL ? "" : request_json);
    result = caml_callback_exn(*callback, request);
    if (Is_exception_result(result)) {
      response = replace_response(
        "{\"apiVersion\":1,\"ok\":false,\"result\":null,\"error\":{\"code\":"
        "\"ocaml_exception\",\"message\":\"The OCaml core raised an exception\"}}");
    } else {
      response = replace_response(String_val(result));
    }
  }
  pthread_mutex_unlock(&ocaml_demo_call_mutex);
  CAMLreturnT(const char *, response);
}
