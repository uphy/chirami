// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Fusen",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.3.0"),
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
        .package(url: "https://github.com/raspu/Highlightr", from: "2.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "Fusen",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Highlightr", package: "Highlightr"),
            ],
            path: "Fusen",
            exclude: [
                "Info.plist",
                "Fusen.entitlements",
                "Resources",
            ]
        )
    ]
)
