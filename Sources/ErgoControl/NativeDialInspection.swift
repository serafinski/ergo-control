import Foundation
import AppKit
import ErgoDevice

enum NativeDialInspection {
    /// Use the same exact-device journal recovery as app startup. This cannot
    /// select an arbitrary mode or discard an unverified restoration record.
    static func restoreKeyboardCommandLine() -> Never {
        let controller = BluetoothController()
        guard controller.restoreOwed else { print("No pending keyboard restoration."); exit(0) }
        controller.connect()
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if !controller.restoreOwed {
                print(controller.status); exit(0)
            }
        }
        print("Restoration remains pending: \(controller.status)"); exit(1)
    }

    static func readPowerCommandLine() -> Never {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "dev.local.ergocontrol.app")
            .contains(where: { $0.processIdentifier != getpid() }) else {
            print("Quit Ergo Control before reading keyboard power settings."); exit(1)
        }
        let journal = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ErgoControl/Bluetooth/pending-restoration.json")
        guard !FileManager.default.fileExists(atPath: journal.path) else {
            print("Finish keyboard restoration before reading power settings."); exit(1)
        }
        let controller = BluetoothController()
        controller.connect()
        let deadline = Date().addingTimeInterval(30)
        var started = false, finished = false
        while !finished && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if controller.ready && !controller.busy && !started {
                started = true
                controller.inspectPowerSettings { rows in
                    rows.forEach { print($0) }; finished = true
                }
            }
        }
        if !finished { print("Power inspection stopped: \(controller.status)") }
        exit(finished ? 0 : 1)
    }

    static func readLightingCommandLine() -> Never {
        let journal = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ErgoControl/Bluetooth/pending-restoration.json")
        guard !FileManager.default.fileExists(atPath: journal.path) else {
            print("Stop mappings and finish keyboard restoration before running this diagnostic."); exit(1)
        }
        let controller = BluetoothController()
        controller.connect()
        let deadline = Date().addingTimeInterval(25)
        var started = false
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if controller.ready && !controller.busy && !started {
                started = true
                controller.refreshKeyboardLighting()
            }
            if started && !controller.keyboardEffectBusy {
                print("Advertised effect IDs: \(controller.keyboardEffectIDs)")
                print(controller.keyboardEffectStatus)
                if let effect = controller.currentKeyboardEffect { print("Effect payload: \(Array(effect.payload))") }
                exit(controller.currentKeyboardEffect == nil ? 1 : 0)
            }
        }
        print("Lighting inspection stopped: \(controller.status)"); exit(1)
    }

    static func runCommandLine() -> Never {
        let journal = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ErgoControl/Bluetooth/pending-restoration.json")
        guard !FileManager.default.fileExists(atPath: journal.path) else {
            print("Finish restoring the keyboard in Ergo Control first."); exit(1)
        }
        let controller = BluetoothController()
        controller.connect()
        let deadline = Date().addingTimeInterval(25)
        var started = false, finished = false
        while !finished && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if controller.ready && !controller.busy && !started {
                started = true
                controller.inspectNativeDial { rows in
                    rows.forEach { print($0) }
                    finished = true
                }
            }
        }
        if !finished { print("Bluetooth inspection stopped: \(controller.status)") }
        exit(finished ? 0 : 1)
    }
}
