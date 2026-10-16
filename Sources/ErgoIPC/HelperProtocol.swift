import Foundation
import Security

public enum HelperIdentity {
    public static let service = "dev.local.ergocontrol.inputhelper"
    // Keep the installed executable/TCC identity and XPC endpoint stable while
    // separating its launchd label from the former bundled SMAppService job.
    public static let localService = service + ".local"
    public static let plist = service + ".plist"
    public static let app = "dev.local.ergocontrol.app"
    public static let installedExecutable = "/Library/PrivilegedHelperTools/" + service
    public static let installedPlist = "/Library/LaunchDaemons/" + plist
}

// The privileged side exposes no commands, paths, output events, or configuration writes.
@objc public protocol InputHelperProtocol {
    func permission(withReply reply: @escaping (Int32) -> Void)
    func begin(withReply reply: @escaping (Int32, String) -> Void)
    func renew(_ acknowledgedReport: UInt64, withReply reply: @escaping (Bool) -> Void)
    func end(withReply reply: @escaping () -> Void)
}

@objc public protocol InputClientProtocol {
    func report(_ reportID: UInt32, bytes: Data, sequence: UInt64)
    func stopped(_ reason: String)
}

public enum PeerSigning {
    public static func hash(at url: URL) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw NSError(domain: "ErgoSigning", code: 1, userInfo: [NSLocalizedDescriptionKey: "The input helper's signature is invalid. Rebuild the app before enabling full control."])
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
              let info = information as? [String: Any], let hash = info[kSecCodeInfoUnique as String] as? Data else {
            throw NSError(domain: "ErgoSigning", code: 2, userInfo: [NSLocalizedDescriptionKey: "The input helper's signature could not be read."])
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    public static func requirement(identifier: String, hash: String) -> String {
        // Callers supply fixed identifiers and hashes from Security, never user-entered strings.
        "identifier \"\(identifier)\" and cdhash H\"\(hash)\""
    }
}
