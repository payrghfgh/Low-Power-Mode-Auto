// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LowPowerAuto",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LowPowerAuto", targets: ["LowPowerAuto"])
    ],
    targets: [
        .executableTarget(
            name: "LowPowerAuto",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
