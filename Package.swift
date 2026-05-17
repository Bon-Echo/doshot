// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DoShot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DoShot", targets: ["DoShot"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "DoShot",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/DoShot",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
