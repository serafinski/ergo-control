// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ErgoControl",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ErgoProbe", targets: ["ErgoProbe"]),
               .executable(name: "ErgoBluetooth", targets: ["ErgoBluetooth"])],
    targets: [
        .target(name: "ErgoCore"),
        .executableTarget(name: "ErgoProbe", dependencies: ["ErgoCore"],
                          linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreBluetooth")]),
        .executableTarget(name: "ErgoBluetooth", dependencies: ["ErgoCore"],
                          linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreBluetooth")]),
        .testTarget(name: "ErgoCoreTests", dependencies: ["ErgoCore"])
    ]
)
