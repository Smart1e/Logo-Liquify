// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "IconChanger",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "IconChanger", targets: ["IconChanger"]),
    ],
    targets: [
        .executableTarget(
            name: "IconChanger",
            path: "Sources/IconChanger",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ]
        ),
    ]
)
