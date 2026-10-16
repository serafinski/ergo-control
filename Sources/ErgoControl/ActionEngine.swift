import AppKit
import ApplicationServices
import ErgoCore

enum MacKeys {
    static let codes: [UInt8: CGKeyCode] = {
        var result: [UInt8: CGKeyCode] = [:]
        let letters: [CGKeyCode] = [0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6]
        for (i, code) in letters.enumerated() { result[UInt8(i + 4)] = code }
        for (i, code) in [18,19,20,21,23,22,26,28,25,29].enumerated() { result[UInt8(i + 30)] = CGKeyCode(code) }
        let other: [UInt8: CGKeyCode] = [40:36,41:53,42:51,43:48,44:49,45:27,46:24,47:33,48:30,49:42,50:10,
            51:41,52:39,53:50,54:43,55:47,56:44,57:57,70:105,71:107,72:113,73:114,74:115,75:116,76:117,
            77:119,78:121,79:124,80:123,81:125,82:126,83:71,84:75,85:67,86:78,87:69,88:76,
            89:83,90:84,91:85,92:86,93:87,94:88,95:89,96:91,97:92,98:82,99:65,100:10,101:110,103:81,
            104:105,105:107,106:113,107:106,108:64,109:79,110:80,111:90,
            224:59,225:56,226:58,227:55,228:62,229:60,230:61,231:54]
        result.merge(other) { a, _ in a }
        for (i, code) in [122,120,99,118,96,97,98,100,101,109,103,111].enumerated() { result[UInt8(i + 58)] = CGKeyCode(code) }
        return result
    }()
    static func flags(_ modifiers: UInt8) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers & 0x11 != 0 { flags.insert(.maskControl) }
        if modifiers & 0x22 != 0 { flags.insert(.maskShift) }
        if modifiers & 0x44 != 0 { flags.insert(.maskAlternate) }
        if modifiers & 0x88 != 0 { flags.insert(.maskCommand) }
        // The device-dependent left/right bits accompany native flagsChanged
        // events. Global hotkey consumers can inspect these as well.
        let deviceBits: [UInt64] = [0x1,0x2,0x20,0x8,0x2000,0x4,0x40,0x10]
        for bit in 0..<8 where modifiers & (1 << bit) != 0 {
            flags.formUnion(CGEventFlags(rawValue: deviceBits[bit]))
        }
        return flags
    }

    static func event(usage: UInt8, pressed: Bool, repeated: Bool, modifiers: UInt8,
                      capsLock: Bool, source: CGEventSource?) -> CGEvent? {
        guard let code = codes[usage],
              let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: pressed) else { return nil }
        // CGEvent adds the native keypad/function flags to arrow keys. Preserve
        // that metadata instead of replacing every flag with the modifier mask.
        let intrinsic = event.flags.intersection([.maskNumericPad, .maskSecondaryFn])
        if usage >= 224 || usage == 57 { event.type = .flagsChanged }
        event.flags = intrinsic.union(flags(modifiers))
        if capsLock { event.flags.insert(.maskAlphaShift) }
        if repeated { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        return event
    }
}

final class ActionEngine {
    var onCycle: (() -> Void)?
    var onBrightness: ((Int) -> Void)?
    var onBattery: (() -> Void)?
    var onError: ((String) -> Void)?
    var physicalModifiers: UInt8 = 0
    private let source = CGEventSource(stateID: .privateState)
    private var down: Set<UInt8> = []
    private var heldMedia: Set<UInt16> = []
    private var jobs: [DispatchWorkItem] = []
    private var tasks: [Process] = []
    private var repeating: UInt8?
    private var repeatTimer: Timer?
    private var macroActive = false
    private var generation = 0
    private var capsLock = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    private var nativeOwners = NativeKeyOwners()
    private var appSwitcher = DialAppSwitcher()
    private var switcherTimer: Timer?
    private let keyOutput: ((KeyboardOutput, Bool) -> Void)?
    private let mediaOutput: ((UInt16, Bool) -> Void)?
    private let repeatTiming: () -> NativeKeyboardTiming
    private let applicationToggle = ApplicationToggle()

    init(mediaOutput: ((UInt16, Bool) -> Void)? = nil,
         repeatTiming: @escaping () -> NativeKeyboardTiming = {
             NativeKeyboardTiming(delay: NSEvent.keyRepeatDelay, interval: NSEvent.keyRepeatInterval)
         }, keyOutput: ((KeyboardOutput, Bool) -> Void)? = nil) {
        self.keyOutput = keyOutput; self.mediaOutput = mediaOutput
        self.repeatTiming = repeatTiming
    }

    func key(_ usage: UInt8, pressed: Bool, repeated: Bool = false, modifiers: UInt8? = nil, tracked: Bool = true) {
        guard MacKeys.codes[usage] != nil else { onError?("This keyboard key needs support (\(usage)); mappings were stopped"); return }
        guard let event = MacKeys.event(usage: usage, pressed: pressed, repeated: repeated,
                                       modifiers: modifiers ?? physicalModifiers, capsLock: capsLock, source: source) else { return }
        if let keyOutput { keyOutput(KeyboardOutput(usage, pressed: pressed, modifiers: modifiers ?? physicalModifiers), repeated) }
        else { event.post(tap: .cghidEventTap) }
        if !repeated && tracked {
            if pressed { down.insert(usage) } else { down.remove(usage) }
        }
    }

    func relay(_ usage: UInt8, pressed: Bool, owner: String? = nil) {
        endAppSwitcher()
        guard nativeOwners.change(usage, owner: owner ?? "key:\(usage)", pressed: pressed) else { return }
        if usage == 57 && pressed { capsLock.toggle() }
        key(usage, pressed: pressed)
        guard usage < 224, usage != 57 else { return }
        if pressed {
            repeatTimer?.invalidate(); repeating = usage
            let timing = repeatTiming()
            repeatTimer = Timer(timeInterval: timing.delay, repeats: false) { [weak self] _ in
                guard let self, self.repeating == usage else { return }
                self.endAppSwitcher()
                self.key(usage, pressed: true, repeated: true)
                self.repeatTimer = Timer(timeInterval: timing.interval, repeats: true) { [weak self] _ in
                    self?.endAppSwitcher()
                    self?.key(usage, pressed: true, repeated: true)
                }
                if let timer = self.repeatTimer { RunLoop.main.add(timer, forMode: .common) }
            }
            if let repeatTimer { RunLoop.main.add(repeatTimer, forMode: .common) }
        } else if repeating == usage { repeatTimer?.invalidate(); repeatTimer = nil; repeating = nil }
    }

    func media(_ usage: UInt16, pressed: Bool) -> Bool {
        endAppSwitcher()
        let codes: [UInt16: Int] = [0xe9:0,0xea:1,0x6f:2,0x70:3,0xe2:7,0xcd:16,0xb5:17,0xb6:18,0xb3:19,0xb4:20]
        guard let code = codes[usage] else { return false }
        let data = (code << 16) | ((pressed ? 0xa : 0xb) << 8)
        if let mediaOutput { mediaOutput(usage, pressed) }
        else {
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8, data1: data, data2: -1)?.cgEvent else { return false }
            event.post(tap: .cghidEventTap)
        }
        if pressed { heldMedia.insert(usage) } else { heldMedia.remove(usage) }
        return true
    }

    func perform(_ action: MappingAction, fromDial: Bool = false) {
        do {
            if fromDial, action.kind == .shortcut,
               let events = appSwitcher.step(try KeyChord(action.value), physicalModifiers: physicalModifiers) {
                outputSwitcher(events)
                switcherTimer?.invalidate()
                let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in self?.endAppSwitcher() }
                switcherTimer = timer; RunLoop.main.add(timer, forMode: .common)
                return
            }
            endAppSwitcher()
            switch action.kind {
            case .shortcut: chord(try KeyChord(action.value))
            case .macro: run(try MacroStep.parse(action.value))
            case .text: type(action.value)
            case .application:
                let url = URL(fileURLWithPath: action.value)
                guard url.pathExtension == "app" else { throw MappingValidationError.message("Choose an application") }
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, error in
                    if let error { DispatchQueue.main.async { self?.onError?(error.localizedDescription) } }
                }
            case .toggleApplication:
                try applicationToggle.perform(URL(fileURLWithPath: action.value)) { [weak self] message in
                    self?.onError?(message)
                }
            case .script:
                guard FileManager.default.fileExists(atPath: action.value) else { throw MappingValidationError.message("The selected script is missing") }
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = [action.value]; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                guard tasks.filter(\.isRunning).count < 3 else { return }
                try process.run(); tasks.removeAll { !$0.isRunning }; tasks.append(process)
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { if process.isRunning { process.terminate() } }
            case .scroll:
                let horizontal = action.value == "left" || action.value == "right"
                let amount: Int32 = action.value == "down" || action.value == "right" ? -3 : 3
                CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2,
                        wheel1: horizontal ? 0 : amount, wheel2: horizontal ? amount : 0, wheel3: 0)?.post(tap: .cghidEventTap)
            case .media:
                let usages: [String: UInt16] = ["volumeUp":0xe9,"volumeDown":0xea,"mute":0xe2,"playPause":0xcd,"next":0xb5,"previous":0xb6]
                if let usage = usages[action.value] { _ = media(usage, pressed: true); _ = media(usage, pressed: false) }
            case .cycleDial: onCycle?()
            case .battery: onBattery?()
            case .keyboardBrightness:
                guard action.value == "up" || action.value == "down" else { throw MappingValidationError.message("Choose Increase or Decrease for keyboard brightness") }
                onBrightness?(action.value == "up" ? 1 : -1)
            case .standard, .disabled, .layer: break
            }
        } catch { onError?(error.localizedDescription) }
    }

    private func chord(_ chord: KeyChord) {
        endAppSwitcher()
        let combined = chord.modifiers
        key(chord.usage, pressed: true, modifiers: combined)
        key(chord.usage, pressed: false, modifiers: physicalModifiers)
    }
    private func type(_ text: String) {
        endAppSwitcher()
        let utf16 = Array(text.utf16)
        var offset = 0
        while offset < utf16.count {
            var length = min(20, utf16.count - offset)
            if offset + length < utf16.count, (0xd800...0xdbff).contains(utf16[offset + length - 1]) { length -= 1 }
            let chunk = Array(utf16.dropFirst(offset).prefix(length))
            for pressed in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: pressed) else { continue }
                chunk.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: $0.baseAddress) }
                event.flags = []; event.post(tap: .cghidEventTap)
            }
            offset += length
        }
    }
    private func run(_ steps: [MacroStep]) {
        guard !macroActive else { return }
        macroActive = true; let ticket = generation
        var elapsed = 0.0
        for step in steps {
            if case .delay(let ms) = step { elapsed += Double(ms) / 1000; continue }
            let job = DispatchWorkItem { [weak self] in
                guard let self, self.generation == ticket else { return }
                switch step { case .chord(let chord): self.chord(chord); case .text(let text): self.type(text); case .delay: break }
            }
            jobs.append(job); DispatchQueue.main.asyncAfter(deadline: .now() + elapsed, execute: job)
            elapsed += 0.025
        }
        let end = DispatchWorkItem { [weak self] in
            guard let self, self.generation == ticket else { return }
            self.macroActive = false; self.jobs.removeAll()
        }
        jobs.append(end); DispatchQueue.main.asyncAfter(deadline: .now() + elapsed, execute: end)
    }
    private func outputSwitcher(_ events: [KeyboardOutput]) {
        for event in events { key(event.usage, pressed: event.pressed, modifiers: event.modifiers, tracked: false) }
    }
    func endAppSwitcher() {
        switcherTimer?.invalidate(); switcherTimer = nil
        outputSwitcher(appSwitcher.finish(physicalModifiers: physicalModifiers))
    }
    func stop() {
        endAppSwitcher()
        applicationToggle.cancelPending()
        generation += 1; jobs.forEach { $0.cancel() }; jobs.removeAll(); macroActive = false
        repeatTimer?.invalidate(); repeatTimer = nil; repeating = nil
        tasks.filter(\.isRunning).forEach { $0.terminate() }; tasks.removeAll()
        physicalModifiers = 0
        for usage in down.sorted() { key(usage, pressed: false, modifiers: 0) }
        down.removeAll()
        nativeOwners = NativeKeyOwners()
        for usage in heldMedia.sorted() { _ = media(usage, pressed: false) }
        heldMedia.removeAll()
    }
}
