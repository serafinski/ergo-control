import AppKit
import Darwin
import ErgoCore
import ErgoDevice
import ErgoUSBResearch

/// Research entry point inside the already signed app, retaining its Bluetooth
/// permission identity. Normal GUI startup never invokes these experiments.
enum LightingLabRunner {
    private final class Session {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ErgoControl/LightingLab", isDirectory: true)
        var journal: URL { folder.appendingPathComponent("pending-lighting.json") }
        var recovery: LightingLabRecovery { LightingLabRecovery(url: journal) }
        var stopped = false
        var signals: [DispatchSourceSignal] = []
        private var lock: Int32 = -1
        private var report: FileHandle?

        init() throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            lock = Darwin.open(folder.appendingPathComponent("session.lock").path, O_CREAT | O_RDWR, 0o600)
            guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
                if lock >= 0 { Darwin.close(lock); lock = -1 }
                throw LightingLabError.message("Another lighting test is running.")
            }
            for number in [SIGINT, SIGTERM, SIGHUP] {
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
                source.setEventHandler { [weak self] in self?.stopped = true }
                source.resume(); signals.append(source)
            }
            let url = folder.appendingPathComponent("test-\(UUID().uuidString).jsonl")
            guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                                 attributes: [.posixPermissions: 0o600]) else {
                throw LightingLabError.message("Cannot create lighting test report.")
            }
            report = try FileHandle(forWritingTo: url)
            print("Report: \(url.path)")
        }

        deinit {
            signals.forEach { $0.cancel() }
            try? report?.close()
            if lock >= 0 { Darwin.close(lock) }
        }

        func log(_ event: String, _ fields: [String: Any] = [:]) {
            var object = fields
            object["event"] = event
            object["time"] = ISO8601DateFormatter().string(from: Date())
            if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
                try? report?.write(contentsOf: data + Data([10]))
            }
        }

        func wait(_ seconds: Double, interruptible: Bool = true) {
            let deadline = ProcessInfo.processInfo.systemUptime + seconds
            while ProcessInfo.processInfo.systemUptime < deadline && (!interruptible || !stopped) {
                RunLoop.main.run(until: Date().addingTimeInterval(0.025))
            }
        }

        func until(_ condition: () -> Bool, seconds: Double, interruptible: Bool = true) throws {
            let deadline = ProcessInfo.processInfo.systemUptime + seconds
            while !condition() {
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    throw LightingLabError.message("Lighting operation timed out.")
                }
                if interruptible && stopped { throw LightingLabError.message("Test stopped.") }
                wait(0.05, interruptible: interruptible)
            }
        }

    }

    static func runCommandLine(_ args: [String]) -> Never {
        setbuf(stdout, nil)
        if args == ["list"] {
            for pattern in LightingLabPattern.allCases {
                let connection = pattern == .nativeWave || pattern == .throughput ? "Bluetooth with --experimental-frames" : pattern.requiresZones ? "USB; Bluetooth with --experimental-frames" : "Bluetooth or USB"
                print("\(pattern.rawValue): \(pattern.explanation) [\(connection)]")
            }
            exit(0)
        }
        // Fixed argument grammar; there is no arbitrary effect, rate or opcode.
        guard [2, 6, 7].contains(args.count),
              ["run", "restore"].contains(args[0]), ["bluetooth", "usb"].contains(args[1]),
              (args[0] == "restore" ? args.count == 2 : args.count >= 6),
              args.count != 7 || args[6] == "--experimental-frames" else { usage() }
        let restore = args[0] == "restore"
        var pattern = LightingLabPattern.presets
        var duration = 6.0
        if !restore {
            guard args[2] == "--pattern", let selected = LightingLabPattern(rawValue: args[3]),
                  args[4] == "--seconds", let seconds = Double(args[5]), seconds.isFinite,
                  (2...30).contains(seconds) else { usage() }
            pattern = selected; duration = seconds
            if (pattern == .throughput || pattern == .nativeWave) && args[1] != "bluetooth" { usage() }
            if args[1] == "bluetooth" && (pattern.requiresZones || pattern == .nativeWave) && args.count != 7 {
                print("Bluetooth zone tests require --experimental-frames to opt into the research path."); exit(2)
            }
        }
        let otherApp = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.local.ergocontrol.app")
            .contains { $0.processIdentifier != getpid() }
        guard !otherApp else { print("Quit Ergo Control from its menu bar before running the lighting lab."); exit(1) }
        let modeJournal = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ErgoControl/Bluetooth/pending-restoration.json")
        guard !FileManager.default.fileExists(atPath: modeJournal.path) else {
            print("Stop mappings and finish keyboard restoration in Ergo Control first."); exit(1)
        }
        do {
            let session = try Session()
            if !restore && FileManager.default.fileExists(atPath: session.journal.path) {
                throw LightingLabError.message("A previous lighting test needs recovery. Run the restore command first.")
            }
            let loaded: LightingLabSnapshot?
            if restore {
                guard FileManager.default.fileExists(atPath: session.journal.path) else {
                    print("No pending lighting restoration."); exit(0)
                }
                let value = try session.recovery.load()
                guard value.connection == args[1] else {
                    throw LightingLabError.message("Use the connection saved by the previous test: \(value.connection).")
                }
                loaded = value
            } else { loaded = nil }
            if args[1] == "usb" {
                try runUSB(session, pattern: pattern, duration: duration, recovery: loaded)
            } else {
                try runBluetooth(session, pattern: pattern, duration: duration, recovery: loaded)
            }
            exit(session.stopped ? 130 : 0)
        } catch {
            print("Lighting lab: \(error.localizedDescription)")
            print("If restoration is pending, reconnect the same keyboard and run the matching restore command.")
            exit(1)
        }
    }

    private static func usage() -> Never {
        print("Usage: --lighting-lab list")
        print("       --lighting-lab run bluetooth|usb --pattern NAME --seconds 2…30 [--experimental-frames]")
        print("       --lighting-lab restore bluetooth|usb")
        exit(2)
    }

    private static func runUSB(_ session: Session, pattern: LightingLabPattern, duration: Double,
                               recovery: LightingLabSnapshot?) throws {
        let usb = try USBLightingConnection()
        if let recovery {
            guard recovery.identity == usb.identity else { throw LightingLabError.message("Recovery belongs to another keyboard.") }
            try session.recovery.restore(connection: "usb", identity: usb.identity, apply: usb.setEffect, read: usb.readEffect)
            print("Previous effect restored and verified."); session.log("restored"); return
        }
        let original = try usb.readEffect()
        try session.recovery.save(LightingLabSnapshot(connection: "usb", identity: usb.identity, effect: original))
        print("Original effect saved. Brightness is unchanged; use a nonzero brightness to see the test.")
        session.log("start", ["connection": "usb", "pattern": pattern.rawValue, "seconds": duration])
        var failure: Error?
        do {
            if pattern == .presets {
                for (name, effect) in LightingLabPattern.presetSteps {
                    if session.stopped { break }
                    print("Showing: \(name)")
                    try usb.setEffect(effect)
                    session.log("effect_verified", ["name": name, "payload": Array(effect.payload)])
                    session.wait(duration)
                }
            } else {
                print("Testing: \(pattern.explanation). This temporarily replaces the keyboard backlight.")
                _ = try usb.exchange(.customEffect)
                let selector = Array(try usb.exchange(.readEffect))
                guard selector.count >= 6, Array(selector.prefix(3)) == [0, 0, 8] else {
                    throw LightingLabError.message("Keyboard did not enter custom-frame lighting.")
                }
                let started = ProcessInfo.processInfo.systemUptime
                var frames = 0
                while !session.stopped && ProcessInfo.processInfo.systemUptime - started < duration {
                    let t = ProcessInfo.processInfo.systemUptime - started
                    _ = try usb.exchange(.frame(pattern.frame(at: t)))
                    frames += 1
                    session.wait(0.12) // At most 5 frames/sec including the 80 ms reply wait.
                }
                session.log("frames_acknowledged", ["count": frames])
                print("Sent \(frames) acknowledged frames. Visible output still needs your observation.")
            }
        } catch { failure = error; session.log("test_error", ["message": error.localizedDescription]) }
        print("Restoring previous effect…")
        do {
            try session.recovery.restore(connection: "usb", identity: usb.identity, apply: usb.setEffect, read: usb.readEffect)
            session.log("restored"); print("Previous effect restored and verified.")
        } catch {
            session.log("restore_failed", ["message": error.localizedDescription])
            throw LightingLabError.message("Restoration remains pending: \(error.localizedDescription)")
        }
        if let failure { throw failure }
    }

    private static func runBluetooth(_ session: Session, pattern: LightingLabPattern, duration: Double,
                                     recovery: LightingLabSnapshot?) throws {
        let controller = BluetoothController()
        controller.connect()
        try session.until({ controller.ready && !controller.busy }, seconds: 25)
        guard let identity = controller.connectedDeviceIdentity else {
            throw LightingLabError.message("Keyboard identity is unavailable.")
        }
        if let recovery, recovery.identity != identity {
            throw LightingLabError.message("Recovery belongs to another keyboard.")
        }
        let profileZero = recovery.map { $0.bluetoothProfile == 0 } ?? (pattern.requiresZones || pattern == .nativeWave)
        var selectedRegion: UInt8 = recovery?.bluetoothRegion ?? 0
        func command(_ operation: BluetoothLightingLabCommand, queued: Bool = false) throws -> Data {
            try session.until({ !controller.busy }, seconds: 6, interruptible: false)
            var result: Result<Data, Error>?
            controller.runLightingLabCommand(operation, region: selectedRegion, queueFrameWrites: queued) { result = $0 }
            try session.until({ result != nil }, seconds: 7, interruptible: false)
            return try result!.get()
        }
        if profileZero && recovery == nil {
            let regions = Array(try command(.readRegions))
            guard !regions.isEmpty, regions.count <= 32, Set(regions).count == regions.count else {
                throw LightingLabError.message("The keyboard returned an invalid lighting-region list.")
            }
            // Use a hardware-reported region, never scan guessed target IDs.
            selectedRegion = regions.first(where: { $0 != 0 }) ?? regions[0]
            print("Reported Bluetooth lighting regions: \(regions); testing region \(selectedRegion).")
            session.log("regions_reported", ["regions": regions, "selected": selectedRegion])
        }
        func read() throws -> KeyboardEffect {
            if profileZero { return try KeyboardEffect(payload: command(.readEffect)) }
            controller.refreshKeyboardLighting()
            try session.until({ !controller.keyboardEffectBusy }, seconds: 15, interruptible: false)
            guard controller.keyboardEffectRequestSucceeded, let effect = controller.currentKeyboardEffect else {
                throw LightingLabError.message(controller.keyboardEffectStatus)
            }
            return effect
        }
        func apply(_ effect: KeyboardEffect) throws {
            if profileZero {
                _ = try command(.restore(effect))
                guard try read() == effect else { throw LightingLabError.message("Bluetooth restoration readback differs.") }
                return
            }
            guard controller.ready, controller.canEditKeyboardLighting else {
                throw LightingLabError.message("Bluetooth disconnected; restoration must be retried.")
            }
            controller.applyKeyboardEffect(effect)
            try session.until({ !controller.keyboardEffectBusy }, seconds: 15, interruptible: false)
            guard controller.keyboardEffectRequestSucceeded, controller.currentKeyboardEffect == effect else {
                throw LightingLabError.message(controller.keyboardEffectStatus)
            }
        }
        let initial = try read()
        if let recovery {
            try session.recovery.restore(connection: "bluetooth", identity: identity, apply: apply, read: read)
            session.log("restored"); print("Previous effect restored and verified."); return
        }
        try session.recovery.save(LightingLabSnapshot(connection: "bluetooth", identity: identity, effect: initial,
                                                      bluetoothProfile: profileZero ? 0 : nil,
                                                      bluetoothRegion: profileZero ? selectedRegion : nil))
        print("Original effect saved. Brightness is unchanged; use a nonzero brightness to see the test.")
        session.log("start", ["connection": "bluetooth", "pattern": pattern.rawValue, "seconds": duration])
        var failure: Error?
        do {
            if pattern == .nativeWave {
                print("Native Wave palette test: requested blue and black")
                _ = try command(.experimentalWavePalette)
                let observed = try read()
                session.log("native_wave_palette_readback", ["payload": Array(observed.payload)])
                print("Native Wave readback: \(Array(observed.payload))")
                session.wait(duration)
            } else if pattern == .presets {
                for (name, effect) in LightingLabPattern.presetSteps {
                    if session.stopped { break }
                    print("Showing: \(name)")
                    try apply(effect)
                    session.log("effect_verified", ["name": name, "payload": Array(effect.payload)])
                    session.wait(duration)
                }
            } else {
                print("Experimental Bluetooth test: \(pattern.explanation)")
                _ = try command(.selectCustom)
                guard try read().id == 8 else { throw LightingLabError.message("Bluetooth custom-frame selection was not confirmed.") }
                session.log("custom_effect_verified")
                if pattern == .throughput {
                    func report(_ phase: String, frames: Int, seconds: Double, samples: [Double]) {
                        let sorted = samples.sorted(), median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
                        session.log("throughput", ["phase": phase, "frames": frames, "seconds": seconds,
                                                   "frames_per_second": Double(frames) / seconds, "median_frame_ms": median * 1000])
                        print("\(phase): \(frames) frames, \(String(format: "%.2f", Double(frames) / seconds)) fps, median \(Int(median * 1000)) ms/frame")
                    }
                    print("First: ordinary acknowledged frame path")
                    var started = ProcessInfo.processInfo.systemUptime, frames = 0, samples: [Double] = []
                    while !session.stopped && ProcessInfo.processInfo.systemUptime - started < duration {
                        let before = ProcessInfo.processInfo.systemUptime
                        _ = try command(.frame(pattern.frame(at: Double(frames) * 0.2)))
                        samples.append(ProcessInfo.processInfo.systemUptime - before); frames += 1
                    }
                    report("serial", frames: frames, seconds: ProcessInfo.processInfo.systemUptime - started, samples: samples)
                    print("Second: queued writes with full keyboard command verification")
                    started = ProcessInfo.processInfo.systemUptime; frames = 0; samples = []
                    while !session.stopped && ProcessInfo.processInfo.systemUptime - started < duration {
                        let before = ProcessInfo.processInfo.systemUptime
                        _ = try command(.frame(pattern.frame(at: Double(frames) * 0.2)), queued: true)
                        samples.append(ProcessInfo.processInfo.systemUptime - before); frames += 1
                    }
                    report("queued-verified", frames: frames, seconds: ProcessInfo.processInfo.systemUptime - started, samples: samples)
                    try controller.disconnectForLightingLab()
                    try session.until({ controller.lightingLabDisconnected }, seconds: 7, interruptible: false)
                    let stream = try BluetoothFrameStream(verifiedIdentity: identity, region: selectedRegion)
                    var streamError: Error?
                    do {
                        stream.connect()
                        try session.until({ stream.ready || stream.failure != nil }, seconds: 20)
                        if let error = stream.failure { throw error }
                        print("Now: queued acknowledged writes, streamed frame responses")
                        started = ProcessInfo.processInfo.systemUptime; frames = 0; samples = []
                        while !session.stopped && ProcessInfo.processInfo.systemUptime - started < duration {
                            let before = ProcessInfo.processInfo.systemUptime
                            var result: Result<Void, Error>?
                            stream.frame(try pattern.frame(at: Double(frames) * 0.2)) { result = $0 }
                            try session.until({ result != nil }, seconds: 5, interruptible: false)
                            try result!.get()
                            samples.append(ProcessInfo.processInfo.systemUptime - before); frames += 1
                            session.wait(max(0, 0.05 - (ProcessInfo.processInfo.systemUptime - before))) // Vendor's 20 fps ceiling.
                        }
                        report("stream", frames: frames, seconds: ProcessInfo.processInfo.systemUptime - started, samples: samples)
                        // Frame replies are drained once at the boundary, not between
                        // frames. Restoration still uses a fresh configuration link.
                        try session.until({ stream.successReplies >= stream.transportFrames || stream.failure != nil }, seconds: 5, interruptible: false)
                        session.log("stream_replies", ["writes_completed": stream.transportFrames, "success_headers": stream.successReplies])
                        if let error = stream.failure { throw error }
                    } catch { streamError = error }
                    stream.stop()
                    try session.until({ stream.disconnected }, seconds: 7, interruptible: false)
                    controller.connect()
                    try session.until({ controller.ready && !controller.busy }, seconds: 25, interruptible: false)
                    guard controller.connectedDeviceIdentity == identity else { throw LightingLabError.message("Keyboard identity changed during the frame test.") }
                    if let streamError { throw streamError }
                } else {
                    let started = ProcessInfo.processInfo.systemUptime
                    var frames = 0
                    while !session.stopped && ProcessInfo.processInfo.systemUptime - started < duration {
                        _ = try command(.frame(pattern.frame(at: ProcessInfo.processInfo.systemUptime - started)))
                        frames += 1
                        session.wait(0.25) // At most four frames/sec; commands remain serialized.
                    }
                    session.log("frames_acknowledged", ["count": frames])
                    print("Sent \(frames) acknowledged Bluetooth frames; watch the physical lighting.")
                }
            }
        } catch { failure = error; session.log("test_error", ["message": error.localizedDescription]) }
        print("Restoring previous effect…")
        do {
            try session.recovery.restore(connection: "bluetooth", identity: identity, apply: apply, read: read)
            session.log("restored"); print("Previous effect restored and verified.")
        } catch {
            session.log("restore_failed", ["message": error.localizedDescription])
            throw LightingLabError.message("Restoration remains pending: \(error.localizedDescription)")
        }
        if let failure { throw failure }
    }
}
