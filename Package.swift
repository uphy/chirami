// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Chirami",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.3.0"),
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
        .package(url: "https://github.com/raspu/Highlightr", from: "2.2.1"),
        .package(url: "https://github.com/swiftlang/swift-testing", from: "0.12.0")
    ],
    targets: [
        .executableTarget(
            name: "Chirami",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Highlightr", package: "Highlightr")
            ],
            path: "Chirami",
            exclude: [
                "Info.plist",
                "Chirami.entitlements",
                "Resources/Assets.xcassets"
            ],
            resources: [
                .copy("Resources/color_schemes.yaml")
            ]
        ),
        .testTarget(
            name: "ChiramiTests",
            dependencies: [
                "Chirami",
                .product(name: "Yams", package: "Yams"),
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "ChiramiTests"
        )
    ]
)
