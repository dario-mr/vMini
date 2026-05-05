// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "vmini",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "vmini", targets: ["vmini"])
    ],
    targets: [
        .executableTarget(
            name: "vmini",
            path: "vmini",
            exclude: [
                "Assets.xcassets",
                "Info.plist"
            ]
        ),
        .testTarget(
            name: "vminiTests",
            dependencies: ["vmini"],
            path: "Tests/vminiTests"
        )
    ]
)
