// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "ocaml-demo-mobile",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OCamlDemo", type: .dynamic, targets: ["OCamlDemo"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.9.5"),
        .package(url: "https://source.skip.tools/skip-ui.git", from: "1.0.0"),
        .package(url: "https://source.skip.tools/skip-ffi.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "OCamlDemo",
            dependencies: [
                "OCamlCoreABI",
                .product(name: "SkipUI", package: "skip-ui"),
                .product(name: "SkipFFI", package: "skip-ffi"),
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .target(
            name: "OCamlCoreABI",
            path: "Sources/OCamlCoreABI",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "OCamlDemoTests",
            dependencies: [
                "OCamlDemo",
                .product(name: "SkipTest", package: "skip"),
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
    ]
)
