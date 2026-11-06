// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "QiqstrCore",
    platforms: [.iOS("26.0")],
    products: [.library(name: "QiqstrCore", targets: ["QiqstrCore"])],
    targets: [
        .binaryTarget(name: "QiqstrCoreFFI", path: "QiqstrCoreFFI.xcframework"),
        .target(
            name: "QiqstrCore",
            dependencies: ["QiqstrCoreFFI"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("SystemConfiguration"), .linkedFramework("Security")]
        ),
    ]
)
