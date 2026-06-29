// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "wInstaller",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "WInstallerCore", targets: ["WInstallerCore"]),
        .executable(name: "WInstallerApp", targets: ["WInstallerApp"])
    ],
    targets: [
        .target(name: "WInstallerCore"),
        .executableTarget(
            name: "WInstallerApp",
            dependencies: ["WInstallerCore"]
        ),
        .testTarget(
            name: "WInstallerCoreTests",
            dependencies: ["WInstallerCore"]
        )
    ]
)
