// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AILSA_SS",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AILSA_SS", targets: ["AILSA_SS"])
    ],
    targets: [
        .executableTarget(
            name: "AILSA_SS",
            path: "Sources/AILSA_SS",
            exclude: [
                "Info-macOS.plist"
            ],
            resources: [
                .copy("Resources/AILSASubSwitch.icns"),
                .copy("Resources/THIRD_PARTY_NOTICES.md"),
                .process("Resources/AILSA_SS-runtime-pricing-bindings-v1.json"),
                .process("Resources/de.lproj"),
                .process("Resources/en.lproj"),
                .process("Resources/es.lproj"),
                .process("Resources/fr.lproj"),
                .process("Resources/it.lproj"),
                .process("Resources/ja.lproj"),
                .process("Resources/ko.lproj"),
                .process("Resources/nl.lproj"),
                .process("Resources/ru.lproj"),
                .process("Resources/zh-Hans.lproj"),
                .process("Resources/zh-Hant.lproj")
            ]
        ),
        .testTarget(
            name: "AILSA_SSTests",
            dependencies: ["AILSA_SS"],
            path: "Tests/AILSA_SSTests"
        )
    ]
)
