// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "posecap",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "posecap", targets: ["posecap"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "posecap",
            dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
        .testTarget(name: "posecapTests", dependencies: ["posecap"]),
    ]
)
