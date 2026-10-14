import Foundation
import ErgoIPC

/// Authenticated, read-only health check. Never opens HID devices or changes permissions.
final class HelperPermissionCheck {
    private var connection: NSXPCConnection?
    private var completion: ((Result<Int32, Error>) -> Void)?
    func start(_ completion: @escaping (Result<Int32, Error>) -> Void) {
        self.completion = completion
        do {
            let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/HelperTools/ErgoInputHelper")
            let hash = try PeerSigning.hash(at: url)
            let connection = NSXPCConnection(machServiceName: HelperIdentity.service, options: .privileged)
            connection.setCodeSigningRequirement(PeerSigning.requirement(identifier: HelperIdentity.service, hash: hash))
            connection.remoteObjectInterface = NSXPCInterface(with: InputHelperProtocol.self)
            self.connection = connection
            let disconnected = { [weak self] in
                DispatchQueue.main.async { self?.finish(.failure(Self.error("The installed helper disconnected. Install the matching helper update, then check again."))) }
            }
            connection.interruptionHandler = disconnected; connection.invalidationHandler = disconnected
            connection.resume()
            let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
                DispatchQueue.main.async { self?.finish(.failure(error)) }
            } as? InputHelperProtocol
            proxy?.permission { [weak self] value in
                DispatchQueue.main.async { self?.finish(.success(value)) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.finish(.failure(Self.error("The helper permission check timed out. No keyboard capture was started.")))
            }
        } catch { finish(.failure(error)) }
    }
    private func finish(_ result: Result<Int32, Error>) {
        guard let callback = completion else { return }
        completion = nil
        let old = connection; connection = nil; old?.invalidate()
        callback(result)
    }
    private static func error(_ message: String) -> NSError {
        NSError(domain: "ErgoHelperPermission", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    deinit { connection?.invalidate() }

    static func runCommandLine() -> Never {
        let check = HelperPermissionCheck()
        check.start { result in
            switch result {
            case .success(let access):
                print("Helper Input Monitoring: \(access == 0 ? "granted" : "not granted") (\(access))")
                print("Read-only check completed; no keyboard was opened.")
                exit(access == 0 ? 0 : 2)
            case .failure(let error): fputs("Helper permission check failed: \(error.localizedDescription)\n", stderr); exit(1)
            }
        }
        withExtendedLifetime(check) { RunLoop.main.run() }
        exit(1)
    }
}
