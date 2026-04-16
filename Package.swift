// swift-tools-version: 5.9
import PackageDescription
import Foundation

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let sherpaInstallRoot = repoRoot
    .appendingPathComponent(".build/prebuilts/sherpa-onnx/build-swift-macos/install", isDirectory: true)
let sherpaLibraryRoot = sherpaInstallRoot.appendingPathComponent("lib", isDirectory: true).path

let package = Package(
    name: "Chirami",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
        .package(url: "https://github.com/swiftlang/swift-testing", from: "0.12.0")
    ],
    targets: [
        .systemLibrary(
            name: "CSherpaOnnx",
            path: "CSherpaOnnx"
        ),
        .executableTarget(
            name: "Chirami",
            dependencies: [
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "Yams", package: "Yams"),
                "CSherpaOnnx"
            ],
            path: "Chirami",
            exclude: [
                "Info.plist",
                "Chirami.entitlements",
                "Resources/Assets.xcassets"
            ],
            resources: [
                .copy("Resources/chirami-default.css"),
                .copy("Resources/editor")
            ],
            linkerSettings: [
                .unsafeFlags(["-L", sherpaLibraryRoot]),
                .linkedLibrary("sherpa-onnx-c-api"),
                .linkedLibrary("sherpa-onnx-core"),
                .linkedLibrary("kaldi-decoder-core"),
                .linkedLibrary("sherpa-onnx-kaldifst-core"),
                .linkedLibrary("sherpa-onnx-fstfar"),
                .linkedLibrary("sherpa-onnx-fst"),
                .linkedLibrary("kaldi-native-fbank-core"),
                .linkedLibrary("kissfft-float"),
                .linkedLibrary("piper_phonemize"),
                .linkedLibrary("espeak-ng"),
                .linkedLibrary("ucd"),
                .linkedLibrary("onnxruntime"),
                .linkedLibrary("ssentencepiece_core"),
                .linkedLibrary("c++")
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
