import Foundation
import SkipFFI
import SwiftUI
#if !SKIP
import OCamlCoreABI
#endif

public final class OCamlDemoCore {
    nonisolated(unsafe) public static let shared = registerNatives(
        OCamlDemoCore(),
        frameworkName: "OCamlDemo",
        libraryName: "ocaml_demo_core"
    )

    private init() {
    }

    /* SKIP EXTERN */ public func ocaml_demo_call(_ request: String) -> String {
        #if OCAML_DEMO_CORE
        return String(cString: OCamlCoreABI.ocaml_demo_call(request))
        #else
        return
            """
            {
              "apiVersion": 1,
              "ok": false,
              "result": null,
              "error": {
                "code": "native_core_unlinked",
                "message": "Build the app with the OCaml core object and OCAML_DEMO_CORE"
              }
            }
            """
        #endif
    }
}

public struct OCamlDemoAppView: View {
    public init() {
    }

    public var body: some View {
        OCamlDemoView(
            call: OCamlDemoCore.shared.ocaml_demo_call,
            databasePath: databasePath
        )
    }

    private var databasePath: String {
        URL.documentsDirectory
            .appendingPathComponent("ocaml-demo.sqlite")
            .path
    }
}
