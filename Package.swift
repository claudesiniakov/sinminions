// swift-tools-version:5.10
import PackageDescription

// Минимальная версия системы — macOS 14; она же продублирована в Info.plist (scripts/build-app.sh).
let package = Package(
    name: "SinMinions",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SinMinions", targets: ["SinMinions"]),
        .library(name: "SinMinionsCore", targets: ["SinMinionsCore"]),
    ],
    targets: [
        .target(name: "SinMinionsCore"),
        .executableTarget(name: "SinMinions", dependencies: ["SinMinionsCore"]),
        .testTarget(name: "SinMinionsCoreTests", dependencies: ["SinMinionsCore"]),
    ]
)
