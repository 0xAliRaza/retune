// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lumen",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Lumen", targets: ["Lumen"])],
    targets: [
        // libmpv from Homebrew (`brew install mpv`); headers are referenced by absolute path in the modulemap.
        .systemLibrary(name: "CMPV", path: "Sources/CMPV"),
        .target(name: "LumenCore"),
        .executableTarget(
            name: "Lumen",
            dependencies: ["LumenCore", "CMPV"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib", "-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib"]),
            ]
        ),
        .testTarget(name: "LumenCoreTests", dependencies: ["LumenCore"]),
    ]
)
