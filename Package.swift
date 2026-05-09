// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "LogoLiquify",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "LogoLiquify", targets: ["LogoLiquify"]),
    ],
    targets: [
        .executableTarget(
            name: "LogoLiquify",
            path: "Sources/LogoLiquify",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ]
        ),
    ]
)
