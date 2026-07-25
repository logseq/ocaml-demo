#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

if [ ! -f "$repo_root/android/jni/ocaml_demo_android_jni.c" ]; then
  echo "Expected Android JNI source at android/jni/ocaml_demo_android_jni.c" >&2
  exit 1
fi

if [ -e "$repo_root/jni" ]; then
  echo "Android JNI sources must live under android/jni, not repo-root jni/" >&2
  exit 1
fi
