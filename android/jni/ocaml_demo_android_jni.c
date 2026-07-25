#include <jni.h>
#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>

static int ocaml_runtime_started = 0;

static void ensure_ocaml_runtime(void) {
  if (!ocaml_runtime_started) {
    static char program_name[] = "ocaml_demo_android";
    char *argv[] = { program_name, NULL };
    caml_startup(argv);
    ocaml_runtime_started = 1;
  }
}

JNIEXPORT jstring JNICALL
Java_com_logseq_ocaml_demoandroid_OCamlDemoAndroidNative_renderNative(
    JNIEnv *env,
    jobject self,
    jstring demo_id) {
  (void)self;
  ensure_ocaml_runtime();
  CAMLparam0();
  CAMLlocal2(ocaml_demo_id, result);
  const value *callback = caml_named_value("ocaml_demo_android_render");
  if (callback == NULL) {
    CAMLreturnT(
      jstring,
      (*env)->NewStringUTF(
        env,
        "{\"type\":\"text\",\"text\":\"OCaml render callback missing\",\"modifiers\":[]}"));
  }

  const char *demo_id_utf8 = (*env)->GetStringUTFChars(env, demo_id, NULL);
  ocaml_demo_id = caml_copy_string(demo_id_utf8);
  (*env)->ReleaseStringUTFChars(env, demo_id, demo_id_utf8);

  result = caml_callback(*callback, ocaml_demo_id);
  CAMLreturnT(jstring, (*env)->NewStringUTF(env, String_val(result)));
}

JNIEXPORT void JNICALL
Java_com_logseq_ocaml_demoandroid_OCamlDemoAndroidNative_dispatchClickNative(
    JNIEnv *env,
    jobject self,
    jstring demo_id,
    jint event_id) {
  (void)self;
  ensure_ocaml_runtime();
  CAMLparam0();
  CAMLlocal2(ocaml_demo_id, result);
  const value *callback = caml_named_value("ocaml_demo_android_dispatch_click");
  if (callback == NULL) CAMLreturn0;

  const char *demo_id_utf8 = (*env)->GetStringUTFChars(env, demo_id, NULL);
  ocaml_demo_id = caml_copy_string(demo_id_utf8);
  (*env)->ReleaseStringUTFChars(env, demo_id, demo_id_utf8);

  value args[2] = { ocaml_demo_id, Val_int(event_id) };
  result = caml_callbackN(*callback, 2, args);
  (void)result;
  CAMLreturn0;
}

JNIEXPORT void JNICALL
Java_com_logseq_ocaml_demoandroid_OCamlDemoAndroidNative_dispatchChangeNative(
    JNIEnv *env,
    jobject self,
    jstring demo_id,
    jint event_id,
    jstring text) {
  (void)self;
  ensure_ocaml_runtime();
  CAMLparam0();
  CAMLlocal3(ocaml_demo_id, ocaml_text, result);
  const value *callback = caml_named_value("ocaml_demo_android_dispatch_change");
  if (callback == NULL) CAMLreturn0;

  const char *demo_id_utf8 = (*env)->GetStringUTFChars(env, demo_id, NULL);
  ocaml_demo_id = caml_copy_string(demo_id_utf8);
  (*env)->ReleaseStringUTFChars(env, demo_id, demo_id_utf8);

  const char *text_utf8 = (*env)->GetStringUTFChars(env, text, NULL);
  ocaml_text = caml_copy_string(text_utf8);
  (*env)->ReleaseStringUTFChars(env, text, text_utf8);

  value args[3] = { ocaml_demo_id, Val_int(event_id), ocaml_text };
  result = caml_callbackN(*callback, 3, args);
  (void)result;
  CAMLreturn0;
}
