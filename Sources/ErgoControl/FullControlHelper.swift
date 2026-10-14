import Foundation
import ServiceManagement
import ErgoIPC
import AppKit
import Security

final class FullControlHelper: ObservableObject {
    @Published private(set) var status = "Full dial control is optional"
    private let service = SMAppService.daemon(plistName: HelperIdentity.plist)
    @Published private(set) var installedForDevelopment = false
    var enabled: Bool { installedForDevelopment || (!usesLocalCertificate && service.status == .enabled) }
    var needsApproval: Bool { !usesLocalCertificate && service.status == .requiresApproval }
    var usesLocalCertificate: Bool {
        var code: SecStaticCode?, info: CFDictionary?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
              let information = info as? [String: Any] else { return true }
        return information[kSecCodeInfoTeamIdentifier as String] == nil
    }
    var installerURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ErgoInputHelper-Install.pkg") }
    var removalURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ErgoInputHelper-Uninstall.pkg") }
    init() { refresh() }
    func refresh() {
        installedForDevelopment = installedHelperMatches()
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
            guard NSWorkspace.shared.open(installerURL) else {
                throw NSError(domain: "ErgoHelperInstall", code: 3, userInfo: [NSLocalizedDescriptionKey: "macOS could not open the helper installer."])
            }
            status = "Complete the input helper installer, then click Refresh status. Mappings remain off."
            return
        }
        try service.register(); refresh()
        if needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }
    func unregister() throws {
        if installedForDevelopment {
            guard FileManager.default.fileExists(atPath: removalURL.path) else {
                throw NSError(domain: "ErgoHelperInstall", code: 2, userInfo: [NSLocalizedDescriptionKey: "The helper uninstaller is missing. Rebuild this app."])
            }
            guard NSWorkspace.shared.open(removalURL) else {
                throw NSError(domain: "ErgoHelperInstall", code: 4, userInfo: [NSLocalizedDescriptionKey: "macOS could not open the helper uninstaller."])
            }
            status = "Complete the helper uninstaller, then click Refresh status."
        } else { try service.unregister(); refresh() }
    }
    func showApproval() { SMAppService.openSystemSettingsLoginItems() }
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
              contents["Label"] as? String == HelperIdentity.service,
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
