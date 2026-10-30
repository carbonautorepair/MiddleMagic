// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiddlePaste",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MiddlePaste", targets: ["MiddlePaste"]),
        .library(name: "MiddlePasteCore", targets: ["MiddlePasteCore"])
    ],
    targets: [
        .target(name: "MiddlePasteCore"),
        .executableTarget(name: "MiddlePaste", dependencies: ["MiddlePasteCore"]),
        // Runs without XCTest/Testing (Command Line Tools only): swift run MiddlePasteChecks
        .executableTarget(name: "MiddlePasteChecks", dependencies: ["MiddlePasteCore"]),
        // Needs full Xcode (Swift Testing).
        .testTarget(name: "MiddlePasteTests", dependencies: ["MiddlePasteCore"])
    ]
)
