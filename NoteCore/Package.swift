// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoteCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NoteCore", targets: ["NoteCore"]),
    ],
    targets: [
        .target(name: "NoteCore"),
        .testTarget(name: "NoteCoreTests", dependencies: ["NoteCore"]),
    ]
)
