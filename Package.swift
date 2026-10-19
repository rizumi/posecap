// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "posecap",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "posecap", targets: ["posecap"])],
    targets: [
        .target(name: "CaptureCore", resources: [.copy("Resources/DeviceHub.applescript")]),
        .executableTarget(name: "posecap", dependencies: ["CaptureCore"]),
        .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"]),
    ]
)
