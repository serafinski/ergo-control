// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ErgoControl",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ErgoProbe", targets: ["ErgoProbe"]),
               .executable(name: "ErgoBluetooth", targets: ["ErgoBluetooth"]),
               .executable(name: "ErgoControl", targets: ["ErgoControl"])],
    targets: [
        .target(name: "ErgoCore"),
        .executableTarget(name: "ErgoProbe", dependencies: ["ErgoCore"],
                          linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreBluetooth")]),
        .target(name: "ErgoDevice", dependencies: ["ErgoCore"],
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreBluetooth")]),
        .executableTarget(name: "ErgoControl", dependencies: ["ErgoCore", "ErgoDevice"],
                          linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreBluetooth"), .linkedFramework("ApplicationServices")]),
        .executableTarget(name: "ErgoBluetooth", dependencies: ["ErgoCore", "ErgoDevice"],
                          linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreBluetooth")]),
        .testTarget(name: "ErgoCoreTests", dependencies: ["ErgoCore"])
    ]
)
