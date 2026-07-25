#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

typedef const char *(*ocaml_demo_call_fn)(const char *);

static int require_contains(const char *response, const char *expected) {
  if (strstr(response, expected) != NULL) {
    return 1;
  }
  fprintf(stderr, "expected response to contain %s, got: %s\n", expected, response);
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: %s path/to/ocaml_demo_mobile_entry.so\n", argv[0]);
    return 2;
  }
  void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (library == NULL) {
    fprintf(stderr, "dlopen failed: %s\n", dlerror());
    return 2;
  }
  ocaml_demo_call_fn call = (ocaml_demo_call_fn)dlsym(library, "ocaml_demo_call");
  if (call == NULL) {
    fprintf(stderr, "dlsym failed: %s\n", dlerror());
    return 2;
  }

  const char *snapshot = call(
    "{\"apiVersion\":1,\"method\":\"snapshot\",\"params\":{\"screen\":\"counter\"}}");
  if (!require_contains(snapshot, "\"ok\":true")
      || !require_contains(snapshot, "\"count\":0")) {
    return 1;
  }

  const char *incremented = call(
    "{\"apiVersion\":1,\"method\":\"dispatch\",\"params\":{\"screen\":\"counter\","
    "\"action\":\"increment\"}}");
  if (!require_contains(incremented, "\"ok\":true")
      || !require_contains(incremented, "\"count\":1")) {
    return 1;
  }

  dlclose(library);
  return 0;
}
