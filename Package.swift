// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "xCleaner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "XCleanerCore", targets: ["XCleanerCore"]),
        .executable(name: "xCleaner", targets: ["xCleaner"])
    ],
    targets: [
        .target(
            name: "XCleanerCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation")
            ]
        ),
        .executableTarget(
            name: "xCleaner",
            dependencies: ["XCleanerCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "XCleanerCoreTests",
            dependencies: ["XCleanerCore"]
        )
    ]
)
