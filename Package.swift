// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chrono",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CSensors",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(
            name: "Chrono",
            dependencies: ["CSensors"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "ChronoTests", dependencies: ["Chrono"]),
    ],
    swiftLanguageModes: [.v5]
)
