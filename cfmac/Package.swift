// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "cfmac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cfmac", targets: ["cfmac"]),
        .executable(name: "cfmac-helper", targets: ["cfmac-helper"]),
        .executable(name: "cfmac-tools", targets: ["cfmac-tools"]),
    ],
    targets: [
        // Reads and writes the System Management Controller (fans, temperatures).
        .target(name: "SMCKit", linkerSettings: [.linkedFramework("IOKit")]),
        // Wire protocol and fan curve shared by the app and the privileged helper.
        .target(name: "FanService", dependencies: ["SMCKit"]),
        // Cleaning, app inventory, maintenance, disk and system engines. No UI.
        .target(name: "CfmacCore", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreServices")]),
        // Completion sounds, synthesized in code.
        .target(name: "SoundKit"),
        // Bundled artwork: planet scenes and menu bar runner frames.
        .target(name: "Artwork", linkerSettings: [.linkedFramework("SceneKit")]),
        .executableTarget(
            name: "cfmac",
            dependencies: ["CfmacCore", "FanService", "SMCKit", "Artwork", "SoundKit"],
            linkerSettings: [.linkedFramework("ServiceManagement"), .linkedFramework("UserNotifications")]
        ),
        .executableTarget(name: "cfmac-helper", dependencies: ["FanService", "SMCKit"]),
        .executableTarget(name: "cfmac-tools", dependencies: ["Artwork", "SoundKit"]),
        .testTarget(name: "CfmacCoreTests", dependencies: ["CfmacCore"]),
        .testTarget(name: "FanServiceTests", dependencies: ["FanService", "SMCKit"]),
        .testTarget(name: "ArtworkTests", dependencies: ["Artwork"]),
        .testTarget(name: "SoundKitTests", dependencies: ["SoundKit"]),
    ],
    swiftLanguageModes: [.v6]
)
