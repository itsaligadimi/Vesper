// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vesper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Vesper", targets: ["Vesper"])
    ],
    targets: [
        .executableTarget(
            name: "Vesper",
            path: "Sources/Vesper",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreGraphics"),
            ]
        )
    ]
)
