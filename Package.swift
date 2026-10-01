// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DoubaoRecall",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DoubaoRecall", targets: ["DoubaoRecall"])
    ],
    targets: [
        .executableTarget(name: "DoubaoRecall"),
        .testTarget(name: "DoubaoRecallTests", dependencies: ["DoubaoRecall"])
    ]
)
