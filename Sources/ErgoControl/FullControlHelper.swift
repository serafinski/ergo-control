import Foundation
import ServiceManagement
import ErgoIPC
import AppKit
import Security

protocol HelperDaemonRegistration {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}
extension SMAppService: HelperDaemonRegistration {}

final class FullControlHelper: ObservableObject {
    @Published private(set) var status = "Full dial control is optional"
    private let service: HelperDaemonRegistration
    private let localOverride: (() -> Bool)?
    private let installedOverride: (() -> Bool)?
    private let openInstaller: (URL) -> Bool
    private let packageDirectory: URL
    @Published private(set) var installedForDevelopment = false
    @Published private(set) var checkingPermission = false
    private var permissionCheck: HelperPermissionCheck?
    var needsStartupRepair: Bool {
        usesLocalCertificate && (service.status == .enabled || service.status == .requiresApproval)
    }
    var enabled: Bool { !needsStartupRepair && (installedForDevelopment || (!usesLocalCertificate && service.status == .enabled)) }
    var needsApproval: Bool { !usesLocalCertificate && service.status == .requiresApproval }
    var usesLocalCertificate: Bool {
        if let localOverride { return localOverride() }
        var code: SecStaticCode?, info: CFDictionary?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
              let information = info as? [String: Any] else { return true }
        return information[kSecCodeInfoTeamIdentifier as String] == nil
    }
    var installerURL: URL { packageDirectory.appendingPathComponent("ErgoInputHelper-Install.pkg") }
    var removalURL: URL { packageDirectory.appendingPathComponent("ErgoInputHelper-Uninstall.pkg") }
    init(service: HelperDaemonRegistration = SMAppService.daemon(plistName: HelperIdentity.plist),
         localOverride: (() -> Bool)? = nil, installedOverride: (() -> Bool)? = nil,
         packageDirectory: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
         openInstaller: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.service = service; self.localOverride = localOverride
        self.installedOverride = installedOverride; self.openInstaller = openInstaller
        self.packageDirectory = packageDirectory
        refresh()
    }
    func refresh() {
        installedForDevelopment = installedOverride?() ?? installedHelperMatches()
        if needsStartupRepair {
            status = "An old bundled-helper registration can override the installed helper after reboot. Choose Repair helper startup, then complete Installer."
            return
        }
        if installedForDevelopment { status = "Local input helper installed · full-control testing is available"; return }
        if usesLocalCertificate {
            status = "This development build needs the local helper installer. macOS does not offer approval for its unnotarized bundled daemon."
            return
        }
        switch service.status {
        case .enabled: status = "Input helper enabled"
        case .requiresApproval: status = "Approve Ergo Control in Login Items & Extensions to enable its input helper"
        case .notRegistered: status = "Full dial control needs the optional input helper"
        case .notFound: status = "Input helper unavailable in this app build"
        @unknown default: status = "Input helper status unavailable"
        }
    }
    func register() throws {
        if usesLocalCertificate {
            guard FileManager.default.fileExists(atPath: installerURL.path) else {
                throw NSError(domain: "ErgoHelperInstall", code: 1, userInfo: [NSLocalizedDescriptionKey: "The helper installer is missing. Rebuild this app."])
            }
            // Booting out a launchd job alone is temporary: Service Management
            // recreates its registered BundleProgram at the next boot. Remove
            // that registration before installing the fixed /Library job.
            try removeLegacyRegistration()
            guard openInstaller(installerURL) else {
                throw NSError(domain: "ErgoHelperInstall", code: 3, userInfo: [NSLocalizedDescriptionKey: "macOS could not open the helper installer."])
            }
            status = "Complete the input helper installer, then click Refresh status. Mappings remain off."
            return
        }
        try service.register(); refresh()
        if needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }
    func unregister() throws {
        if installedForDevelopment || usesLocalCertificate {
            guard FileManager.default.fileExists(atPath: removalURL.path) else {
                throw NSError(domain: "ErgoHelperInstall", code: 2, userInfo: [NSLocalizedDescriptionKey: "The helper uninstaller is missing. Rebuild this app."])
            }
            try removeLegacyRegistration()
            guard openInstaller(removalURL) else {
                throw NSError(domain: "ErgoHelperInstall", code: 4, userInfo: [NSLocalizedDescriptionKey: "macOS could not open the helper uninstaller."])
            }
            status = "Complete the helper uninstaller, then click Refresh status."
        } else { try service.unregister(); refresh() }
    }
    private func removeLegacyRegistration() throws {
        guard needsStartupRepair else { return }
        try service.unregister()
        guard !needsStartupRepair else {
            throw NSError(domain: "ErgoHelperInstall", code: 5, userInfo: [NSLocalizedDescriptionKey: "macOS has not removed the old helper registration yet. Wait a moment, then retry the repair."])
        }
    }
    static func statusCommandLine() -> Never {
        let helper = FullControlHelper()
        print("Bundled daemon registration: \(helper.service.status.rawValue)")
        print("Local certificate: \(helper.usesLocalCertificate)")
        print("Matching installed helper: \(helper.installedForDevelopment)")
        print("Startup repair needed: \(helper.needsStartupRepair)")
        print(helper.status)
        exit(0)
    }
    func showApproval() { SMAppService.openSystemSettingsLoginItems() }
    func checkPermission() {
        guard enabled, !checkingPermission else { return }
        checkingPermission = true
        let check = HelperPermissionCheck(); permissionCheck = check
        status = "Checking helper input permission without opening the keyboard…"
        check.start { [weak self] result in
            guard let self else { return }
            self.checkingPermission = false; self.permissionCheck = nil
            switch result {
            case .success(let access):
                self.status = access == 0 ? "Helper Input Monitoring ready · start a short mapping test"
                    : "Helper Input Monitoring is blocked (\(access)). Enable its separate entry, then check again."
            case .failure(let error): self.status = "Helper permission check failed: " + error.localizedDescription
            }
        }
    }
    private func installedHelperMatches() -> Bool {
        let tool = URL(fileURLWithPath: HelperIdentity.installedExecutable)
        let plist = URL(fileURLWithPath: HelperIdentity.installedPlist)
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/HelperTools/ErgoInputHelper")
        for url in [tool, plist] {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0,
                  let permissions = attributes[.posixPermissions] as? NSNumber,
                  permissions.intValue & 0o022 == 0 else { return false }
        }
        guard let installedHash = try? PeerSigning.hash(at: tool), let expectedHash = try? PeerSigning.hash(at: bundled),
              installedHash == expectedHash, let data = try? Data(contentsOf: plist),
              let contents = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              contents["Label"] as? String == HelperIdentity.localService,
              contents["Program"] as? String == HelperIdentity.installedExecutable,
              (contents["MachServices"] as? [String: Bool])?[HelperIdentity.service] == true else { return false }
        return true
    }
}

private final class InputReceiver: NSObject, InputClientProtocol {
    weak var owner: HelperInputClient?
    let session: UUID
    init(owner: HelperInputClient, session: UUID) { self.owner = owner; self.session = session }
    func report(_ reportID: UInt32, bytes: Data, sequence: UInt64) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.owner?.receive(reportID, bytes, sequence: sequence, session: self.session)
        }
    }
    func stopped(_ reason: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.owner?.failed(reason, session: self.session)
        }
    }
}

final class HelperInputClient {
    var onReport: ((UInt32, Data) -> Void)?
    var onFailure: ((String) -> Void)?
    private var connection: NSXPCConnection?
    private var session: UUID?
    private var heartbeat: Timer?
    private var acknowledged: UInt64 = 0
    private var completion: ((Result<Void, Error>) -> Void)?

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        stop()
        do {
            let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/HelperTools/ErgoInputHelper")
            let hash = try PeerSigning.hash(at: url)
            let connection = NSXPCConnection(machServiceName: HelperIdentity.service, options: .privileged)
            connection.setCodeSigningRequirement(PeerSigning.requirement(identifier: HelperIdentity.service, hash: hash))
            let token = UUID(); session = token; self.completion = completion; self.connection = connection
            connection.remoteObjectInterface = NSXPCInterface(with: InputHelperProtocol.self)
            connection.exportedInterface = NSXPCInterface(with: InputClientProtocol.self)
            connection.exportedObject = InputReceiver(owner: self, session: token)
            let lost = { [weak self] in DispatchQueue.main.async { self?.failed("The input helper disconnected. Native keyboard input will return automatically.", session: token) } }
            connection.interruptionHandler = lost; connection.invalidationHandler = lost
            connection.resume()
            proxy(session: token)?.begin { [weak self] result, message in
                DispatchQueue.main.async {
                    guard let self, self.session == token else { return }
                    guard result == 0 else { self.failed(message, session: token); return }
                    let callback = self.completion; self.completion = nil
                    let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.renew(session: token) }
                    self.heartbeat = timer; RunLoop.main.add(timer, forMode: .common)
                    callback?(.success(()))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, self.session == token, self.completion != nil else { return }
                self.failed("The input helper did not respond. Check its approval in Login Items & Extensions.", session: token)
            }
        } catch { completion(.failure(error)) }
    }
    private func proxy(session token: UUID) -> InputHelperProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            DispatchQueue.main.async { self?.failed(error.localizedDescription, session: token) }
        } as? InputHelperProtocol
    }
    fileprivate func receive(_ id: UInt32, _ data: Data, sequence: UInt64, session token: UUID) {
        guard session == token else { return }
        guard acknowledged < UInt64.max, sequence == acknowledged + 1, (1...6).contains(id), !data.isEmpty, data.count <= 64 else {
            failed("Input delivery changed; mappings stopped", session: token); return
        }
        onReport?(id, data)
        if session == token { acknowledged = sequence }
    }
    func setCapsLock(_ enabled: Bool, completion: @escaping (Int32) -> Void) {
        guard let token = session, self.completion == nil, heartbeat != nil else { return }
        proxy(session: token)?.setCapsLock(enabled) { [weak self] result in
            DispatchQueue.main.async {
                guard self?.session == token else { return }
                completion(result)
            }
        }
    }
    private func renew(session token: UUID) {
        guard session == token else { return }
        proxy(session: token)?.renew(acknowledged) { [weak self] alive in
            if !alive { DispatchQueue.main.async { self?.failed("The input lease ended. Enable mappings to try again.", session: token) } }
        }
    }
    fileprivate func failed(_ message: String, session token: UUID) {
        guard session == token else { return }
        let callback = completion
        stop()
        if let callback { callback(.failure(NSError(domain: "ErgoInputHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))) }
        else { onFailure?(message) }
    }
    func stop() {
        session = nil; completion = nil; acknowledged = 0
        heartbeat?.invalidate(); heartbeat = nil
        let old = connection; connection = nil
        // Invalidation is itself a release request on the daemon side, even if an end RPC is lost.
        (old?.remoteObjectProxy as? InputHelperProtocol)?.end {}
        old?.invalidate()
    }
    deinit { stop() }
}
