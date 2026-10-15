import Foundation

public struct LightingLabSnapshot: Codable {
    public let version: Int
    public let connection: String
    public let identity: String
    public let effect: Data

    public init(connection: String, identity: String, effect: KeyboardEffect) {
        version = 1; self.connection = connection; self.identity = identity; self.effect = effect.payload
    }

    public func validatedEffect() throws -> KeyboardEffect {
        guard version == 1, ["usb", "bluetooth"].contains(connection), !identity.isEmpty else {
            throw LightingLabError.unsupportedOriginal
        }
        let value = try KeyboardEffect(payload: effect)
        _ = try Protocol30Request.keyboardEffect(transaction: 1, effect: value)
        return value
    }
}

/// A saved snapshot must survive every failed or mismatched recovery attempt.
/// Callers create the parent directory privately and hold the session lock.
public struct LightingLabRecovery {
    public let url: URL
    public init(url: URL) { self.url = url }
    public var pending: Bool { FileManager.default.fileExists(atPath: url.path) }

    public func load() throws -> LightingLabSnapshot {
        let snapshot = try JSONDecoder().decode(LightingLabSnapshot.self, from: Data(contentsOf: url))
        _ = try snapshot.validatedEffect()
        return snapshot
    }

    public func save(_ snapshot: LightingLabSnapshot) throws {
        guard !pending else {
            throw LightingLabError.message("A previous lighting test needs recovery. Run the restore command first.")
        }
        _ = try snapshot.validatedEffect()
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func restore(connection: String, identity: String,
                        apply: (KeyboardEffect) throws -> Void,
                        read: () throws -> KeyboardEffect) throws {
        let saved = try load()
        guard saved.connection == connection, saved.identity == identity else {
            throw LightingLabError.message("Recovery belongs to another keyboard or connection.")
        }
        let effect = try saved.validatedEffect()
        try apply(effect)
        guard try read() == effect else {
            throw LightingLabError.message("Restoration readback did not match; the recovery record was retained.")
        }
        try FileManager.default.removeItem(at: url)
    }
}
