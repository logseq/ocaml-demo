package com.logseq.ocaml_demoandroid

import android.content.Context

object OCamlDemoAndroidNative {
    private val loaded: Boolean = runCatching {
        System.loadLibrary("ocaml_demo_android_counter")
    }.isSuccess

    private external fun renderNative(demoId: String): String
    private external fun dispatchClickNative(demoId: String, eventId: Int)
    private external fun dispatchChangeNative(demoId: String, eventId: Int, text: String)

    fun render(context: Context, demoId: String): String =
        if (loaded) {
            renderNative(demoId)
        } else {
            context.assets.open("ocaml_demo_${demoId}.json")
                .bufferedReader()
                .use { it.readText() }
        }

    fun dispatchClick(demoId: String, eventId: Int) {
        if (loaded) dispatchClickNative(demoId, eventId)
    }

    fun dispatchChange(demoId: String, eventId: Int, text: String) {
        if (loaded) dispatchChangeNative(demoId, eventId, text)
    }

    val isNativeLoaded: Boolean = loaded
}
