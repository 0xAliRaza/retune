// swift-tools-version: 6.0
import Foundation
import PackageDescription

// libmpv comes from Homebrew (`brew install mpv`), under whichever prefix this Mac uses.
let homebrewPrefixes = ["/opt/homebrew", "/usr/local"].filter { FileManager.default.fileExists(atPath: "\($0)/include/mpv/client.h") }

let package = Package(
    name: "Retune",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Retune", targets: ["Retune"])],
    targets: [
        .systemLibrary(name: "CMPV", path: "Sources/CMPV", providers: [.brew(["mpv"])]),
        .target(name: "RetuneCore"),
        .executableTarget(
            name: "Retune",
            dependencies: ["RetuneCore", "CMPV"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(homebrewPrefixes.flatMap { ["-Xcc", "-I\($0)/include"] }),
            ],
            linkerSettings: [
                .unsafeFlags(homebrewPrefixes.flatMap { ["-L\($0)/lib", "-Xlinker", "-rpath", "-Xlinker", "\($0)/lib"] }),
            ]
        ),
        .testTarget(name: "RetuneCoreTests", dependencies: ["RetuneCore"]),
    ]
)
