// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Joynite", platforms: [.macOS(.v14)], products: [.executable(name: "Joynite", targets: ["Joynite"]), .executable(name: "JoyniteValidation", targets: ["JoyniteValidation"])], targets: [.target(name: "JoyniteCore"), .executableTarget(name: "Joynite", dependencies: ["JoyniteCore"]), .executableTarget(name: "JoyniteValidation", dependencies: ["JoyniteCore"], path: "Tests/JoyniteCoreTests")])
