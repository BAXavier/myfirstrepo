// swift-tools-version:5.10
import PackageDescription

// Platform-neutral core: models, gesture math, prompt, and HTTP clients.
// Foundation-only, so `swift test` runs on any Mac (and on Linux).
let package = Package(
    name: "CaptureKit",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [.library(name: "CaptureKit", targets: ["CaptureKit"])],
    targets: [
        .target(name: "CaptureKit"),
        .testTarget(name: "CaptureKitTests", dependencies: ["CaptureKit"]),
    ]
)
