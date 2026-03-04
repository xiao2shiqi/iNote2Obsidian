// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iNote2ObsidianNative",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "iNote2ObsidianApp", targets: ["iNote2ObsidianApp"])
    ],
    targets: [
        .executableTarget(
            name: "iNote2ObsidianApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
