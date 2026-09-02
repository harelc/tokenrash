// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tokenrash",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tokenrash", targets: ["Tokenrash"])
    ],
    targets: [
        .executableTarget(
            name: "Tokenrash",
            path: "Sources/Tokenrash"
        )
    ]
)
