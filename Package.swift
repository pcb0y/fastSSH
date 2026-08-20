// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FastSSH",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/jakeheis/Shout.git", from: "0.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "FastSSH",
            dependencies: [
                .product(name: "Shout", package: "Shout"),
            ],
            path: "Sources/FastSSH",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/opt/libssh2/lib", "-L/opt/homebrew/opt/openssl/lib"]),
            ]
        ),
    ]
)
