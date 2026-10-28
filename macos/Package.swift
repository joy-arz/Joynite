// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PlayniteMac", platforms: [.macOS(.v14)], products: [.executable(name: "PlayniteMac", targets: ["PlayniteMac"]), .executable(name: "PlayniteValidation", targets: ["PlayniteValidation"])], targets: [.target(name: "PlayniteCore"), .executableTarget(name: "PlayniteMac", dependencies: ["PlayniteCore"]), .executableTarget(name: "PlayniteValidation", dependencies: ["PlayniteCore"], path: "Tests/PlayniteCoreTests")])
