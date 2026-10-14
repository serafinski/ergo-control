import Foundation
import IOKit.hid
import SystemConfiguration
import Security
import ErgoCore
import ErgoIPC

private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
private func consoleUID() -> uid_t? {
    var uid: uid_t = 0, gid: gid_t = 0
    guard let user = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?,
          user != "loginwindow", uid != 0 else { return nil }
    return uid
}

private func clientRequirement() -> String? {
    var own: SecCode?, secured: SecStaticCode?, information: CFDictionary?
    guard SecCodeCopySelf([], &own) == errSecSuccess, let own,
          SecCodeCopyStaticCode(own, [], &secured) == errSecSuccess, let secured,
          SecCodeCopySigningInformation(secured, [], &information) == errSecSuccess,
          let info = information as? [String: Any],
          let plist = info[kSecCodeInfoPList as String] as? [String: Any],
          let requirement = plist["ErgoAcceptedClientRequirement"] as? String else { return nil }
    var parsed: SecRequirement?
    guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess else { return nil }
    return requirement
}

private final class CaptureService: NSObject, NSXPCListenerDelegate, InputHelperProtocol {
    private let requirement: String
    private var connection: NSXPCConnection?
    private var device: IOHIDDevice?
    private var timer: Timer?
    private var lease = InputLease()
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    init(requirement: String) {
        self.requirement = requirement
        buffer.initialize(repeating: 0, count: 64)
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection candidate: NSXPCConnection) -> Bool {
        // Serialize acceptance, capture, callbacks, and teardown on the main run loop.
        var accepted = false
        let accept = { [self, candidate] in
            guard self.connection == nil, candidate.effectiveUserIdentifier == consoleUID() else { return }
            candidate.setCodeSigningRequirement(self.requirement)
            candidate.exportedInterface = NSXPCInterface(with: InputHelperProtocol.self)
            candidate.exportedObject = self
            candidate.remoteObjectInterface = NSXPCInterface(with: InputClientProtocol.self)
            candidate.interruptionHandler = { [weak self, weak candidate] in
                DispatchQueue.main.async { self?.disconnected(candidate) }
            }
            candidate.invalidationHandler = { [weak self, weak candidate] in
                DispatchQueue.main.async { self?.disconnected(candidate) }
            }
            self.connection = candidate
            candidate.resume(); accepted = true
        }
        if Thread.isMainThread { accept() } else { DispatchQueue.main.sync(execute: accept) }
        return accepted
    }
    private func disconnected(_ candidate: NSXPCConnection?) {
        guard let candidate, connection === candidate else { return }
        release(); connection = nil; candidate.invalidate()
        // IOHID/TCC can cache an earlier denial for the life of a process. Each
        // new session starts a fresh helper; launchd keeps the Mach service available.
        exit(0)
    }
    private var client: InputClientProtocol? {
        guard let peer = connection else { return nil }
        return peer.remoteObjectProxyWithErrorHandler { [weak self, weak peer] _ in
            DispatchQueue.main.async {
                guard let self, let peer, self.connection === peer else { return }
                self.fail("Input connection was lost")
            }
        } as? InputClientProtocol
    }

    func permission(withReply reply: @escaping (Int32) -> Void) {
        let caller = NSXPCConnection.current()
        DispatchQueue.main.async {
            guard self.connection === caller, self.connection?.effectiveUserIdentifier == consoleUID() else {
                reply(-1); return
            }
            reply(Int32(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue))
        }
    }
    func begin(withReply reply: @escaping (Int32, String) -> Void) {
        let caller = NSXPCConnection.current()
        DispatchQueue.main.async { [self] in
            guard let connection = self.connection, connection === caller,
                  connection.effectiveUserIdentifier == consoleUID(), !self.lease.active else {
                reply(kIOReturnNotPermitted, "Full control is already in use or this user is no longer active"); return
            }
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
            IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: ErgoTarget.vendorID,
                kIOHIDProductIDKey: ErgoTarget.productID, kIOHIDTransportKey: ErgoTarget.transport] as CFDictionary)
            let matched = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []).filter {
                ErgoTarget.matches(
                    vendor: (IOHIDDeviceGetProperty($0, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0,
                    product: (IOHIDDeviceGetProperty($0, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0,
                    transport: (IOHIDDeviceGetProperty($0, kIOHIDTransportKey as CFString) as? String ?? ""))
            }
            guard matched.count == 1, let device = matched.first else {
                reply(kIOReturnNoDevice, "Connect exactly one PT Ergo over Bluetooth"); return
            }
            let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            guard result == kIOReturnSuccess else {
                let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue
                reply(result, "The input helper could not open PT Ergo (\(result), permission check \(access)). It will restart when this attempt closes. Check helper Input Monitoring, then retry."); return
            }
            self.device = device; self.lease.begin(now: now())
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(device, self.buffer, 64, { context, result, _, _, id, bytes, count in
                guard let context else { return }
                let service = Unmanaged<CaptureService>.fromOpaque(context).takeUnretainedValue()
                guard result == kIOReturnSuccess, (1...6).contains(id), count > 0, count <= 64 else {
                    service.fail("PT Ergo input changed or capture failed"); return
                }
                guard service.connection?.effectiveUserIdentifier == consoleUID(),
                      let sequence = service.lease.nextReport(now: now()) else {
                    service.fail("The app stopped receiving input; native keyboard input was returned"); return
                }
                service.client?.report(id, bytes: Data(bytes: bytes, count: count), sequence: sequence)
            }, context)
            IOHIDDeviceRegisterRemovalCallback(device, { context, _, _ in
                guard let context else { return }
                Unmanaged<CaptureService>.fromOpaque(context).takeUnretainedValue().fail("PT Ergo disconnected")
            }, context)
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                guard let self else { return }
                if !self.lease.isValid(now: now()) || self.connection?.effectiveUserIdentifier != consoleUID() {
                    self.fail("The input lease expired; native keyboard input was returned")
                }
            }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common)
            reply(kIOReturnSuccess, "Full keyboard control ready")
        }
    }
    func renew(_ acknowledgedReport: UInt64, withReply reply: @escaping (Bool) -> Void) {
        let caller = NSXPCConnection.current()
        DispatchQueue.main.async {
            guard self.connection === caller else { reply(false); return }
            let valid = self.connection?.effectiveUserIdentifier == consoleUID()
                && self.lease.renew(ack: acknowledgedReport, now: now())
            if !valid { self.fail("Input processing stopped; native keyboard input was returned") }
            reply(valid)
        }
    }
    func end(withReply reply: @escaping () -> Void) {
        let caller = NSXPCConnection.current()
        DispatchQueue.main.async { if self.connection === caller { self.release() }; reply() }
    }
    private func fail(_ reason: String) {
        let wasActive = lease.active || device != nil
        release()
        if wasActive { client?.stopped(reason) }
    }
    func release() {
        lease.end(); timer?.invalidate(); timer = nil
        guard let device else { return }
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)); self.device = nil
    }
    deinit { buffer.deallocate() }
}

guard let requirement = clientRequirement() else {
    fputs("Missing or invalid pinned app signature. Build with tools/build_app.sh.\n", stderr); exit(1)
}
if CommandLine.arguments == [CommandLine.arguments[0], "--self-check"] {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    do { _ = try PeerSigning.hash(at: executable) }
    catch { fputs("Helper signature check failed: \(error.localizedDescription)\n", stderr); exit(1) }
    let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    var code: SecStaticCode?, expected: SecRequirement?
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
          SecRequirementCreateWithString(requirement as CFString, [], &expected) == errSecSuccess,
          SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), expected) == errSecSuccess else {
        fputs("Bundled app does not match the pinned signature.\n", stderr); exit(1)
    }
    print("Pinned client requirement: \(requirement)")
    print("Self-check passed; no device opened and no service registered.")
    exit(0)
}
guard geteuid() == 0 else { fputs("The input helper must be started by Service Management.\n", stderr); exit(1) }
private let service = CaptureService(requirement: requirement)
let listener = NSXPCListener(machServiceName: HelperIdentity.service)
listener.delegate = service
var signalSources: [DispatchSourceSignal] = []
for number in [SIGTERM, SIGINT] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler { service.release(); exit(0) }
    source.resume(); signalSources.append(source)
}
listener.resume()
RunLoop.main.run()
