import Foundation
import ErgoDevice

enum NativeDialInspection {
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
