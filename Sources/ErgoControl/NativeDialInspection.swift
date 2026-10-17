import Foundation
import AppKit
import ErgoDevice
import ErgoCore

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

    private struct PowerBackup: Codable {
        let peripheral: UUID
        let settings: KeyboardPowerSettings
    }
    /// Bounded hardware check with a durable backup. Re-running after an
    /// interruption restores the existing backup instead of starting a new test.
    static func testPowerCommandLine() -> Never {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "dev.local.ergocontrol.app")
            .contains(where: { $0.processIdentifier != getpid() }) else { print("Quit Ergo Control first."); exit(1) }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ErgoControl/Bluetooth")
        for journal in ["pending-restoration.json", "pending-brightness.json"] {
            guard !FileManager.default.fileExists(atPath: root.appendingPathComponent(journal).path) else { print("Finish keyboard recovery in Ergo Control first."); exit(1) }
        }
        let backupURL = root.appendingPathComponent("pending-power-test.json")
        let controller = BluetoothController()
        func wait(_ condition: () -> Bool, seconds: Double = 20) throws {
            let end = Date().addingTimeInterval(seconds)
            while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.025)) }
            guard condition() else { throw LightingLabError.message("Power test timed out; backup retained if present.") }
        }
        func read() throws -> KeyboardPowerSettings {
            controller.refreshPowerSettings()
            try wait { !controller.powerSettingsBusy }
            guard let settings = controller.powerSettings else { throw LightingLabError.message(controller.powerSettingsMessage) }
            return settings
        }
        func apply(_ settings: KeyboardPowerSettings) throws {
            controller.applyPowerSettings(KeyboardPowerChanges(brightness: settings.brightness, dimming: settings.dimming, sleep: settings.sleep))
            try wait { !controller.powerSettingsBusy }
            guard controller.powerSettings == settings else { throw LightingLabError.message(controller.powerSettingsMessage) }
        }
        do {
            controller.connect(); try wait({ controller.ready && !controller.busy }, seconds: 25)
            guard let text = controller.connectedDeviceIdentity, let id = UUID(uuidString: text) else { throw LightingLabError.invalidPacket }
            let backup: PowerBackup
            let recovering = FileManager.default.fileExists(atPath: backupURL.path)
            if recovering { backup = try JSONDecoder().decode(PowerBackup.self, from: Data(contentsOf: backupURL)) }
            else {
                backup = PowerBackup(peripheral: id, settings: try read())
                try JSONEncoder().encode(backup).write(to: backupURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
                let file = try FileHandle(forWritingTo: backupURL); try file.synchronize(); try file.close()
            }
            guard backup.peripheral == id else { throw LightingLabError.message("Power backup belongs to another keyboard.") }
            var failure: Error?
            if !recovering {
                do {
                    var test = backup.settings
                    test.brightness = backup.settings.brightness == 26 ? 13 : 26
                    test.dimming = KeyboardDimming(enabled: !backup.settings.dimming.enabled, seconds: backup.settings.dimming.seconds == 180 ? 300 : 180, percentage: backup.settings.dimming.percentage)
                    test.sleep = KeyboardSleep(enabled: !backup.settings.sleep.enabled, seconds: backup.settings.sleep.seconds == 600 ? 900 : 600)
                    try apply(test)
                    print("Brightness, dimming and sleep writes acknowledged and independently read back.")
                    controller.setLightingSuppressed(true)
                    try wait { !controller.powerSettingsBusy }
                    guard controller.lightingOffVerified else { throw LightingLabError.message("Temporary blackout was not verified.") }
                    controller.setLightingSuppressed(false)
                    try wait { !controller.powerSettingsBusy }
                    guard !FileManager.default.fileExists(atPath: root.appendingPathComponent("pending-brightness.json").path) else {
                        throw LightingLabError.message("Brightness recovery remains pending.")
                    }
                    print("Automatic lighting-off and exact brightness restoration verified.")
                } catch { failure = error; print("Test failed: \(error.localizedDescription)") }
            }
            controller.setLightingSuppressed(false)
            try wait { !controller.powerSettingsBusy }
            try apply(backup.settings)
            guard try read() == backup.settings else { throw LightingLabError.message("Original settings did not match; backup retained.") }
            try FileManager.default.removeItem(at: backupURL)
            print("Original brightness, dimming and sleep settings restored and verified.")
            exit(failure == nil ? 0 : 1)
        } catch { print("Power test stopped: \(error.localizedDescription). Any backup was retained; rerun this command to restore it."); exit(1) }
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
