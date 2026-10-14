// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ErgoControl",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ErgoProbe", targets: ["ErgoProbe"]),
               .executable(name: "ErgoBluetooth", targets: ["ErgoBluetooth"]),
               .executable(name: "ErgoControl", targets: ["ErgoControl"]),
               .executable(name: "ErgoInputHelper", targets: ["ErgoInputHelper"])],
    targets: [
        .target(name: "ErgoCore"),
        .target(name: "ErgoIPC", linkerSettings: [.linkedFramework("Security")]),
        .executableTarget(name: "ErgoInputHelper", dependencies: ["ErgoCore", "ErgoIPC"],
                          linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("SystemConfiguration")]),
        .executableTarget(name: "ErgoProbe", dependencies: ["ErgoCore"],
                          linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreBluetooth")]),
        .target(name: "ErgoDevice", dependencies: ["ErgoCore"],
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreBluetooth")]),
        .executableTarget(name: "ErgoControl", dependencies: ["ErgoCore", "ErgoDevice", "ErgoIPC"],
                          linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreBluetooth"), .linkedFramework("ApplicationServices"), .linkedFramework("ServiceManagement")]),
        .executableTarget(name: "ErgoBluetooth", dependencies: ["ErgoCore", "ErgoDevice"],
                          linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreBluetooth")]),
        .testTarget(name: "ErgoCoreTests", dependencies: ["ErgoCore"]),
        .testTarget(name: "ErgoDeviceTests", dependencies: ["ErgoDevice", "ErgoCore"]),
        .testTarget(name: "ErgoControlTests", dependencies: ["ErgoControl", "ErgoCore"])
    ]
)
