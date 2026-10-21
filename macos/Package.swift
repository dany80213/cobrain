// swift-tools-version:6.0
import PackageDescription

// Cobrain: native macOS front end for the WordCraft engine.
// Build the Rust bridge first: `cargo build --release -p cobrain-ffi` (or run scripts/build-app.sh).
let package = Package(
    name: "Cobrain",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CCobrain", path: "Sources/CCobrain"),
        .executableTarget(
            name: "Cobrain",
            dependencies: ["CCobrain"],
            path: "Sources/Cobrain",
            linkerSettings: [
                .unsafeFlags(["-L", "../target/release", "-lcobrain_ffi"]),
                .linkedFramework("Security"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("SystemConfiguration"),
                .linkedLibrary("iconv"),
                .linkedLibrary("c++"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
