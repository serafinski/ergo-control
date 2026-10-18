import AppKit
import ObjectiveC
import Darwin
import ErgoCore

/// Opt-in idle fallback only. MediaPlayer's public Now Playing API describes
/// this app's own session, not the system target. Guard this read-only private
/// interface by selectors/types; never read track metadata or send commands.
final class SystemMediaTarget {
    private let worker = DispatchQueue(label: "dev.local.ergocontrol.media-target", qos: .userInitiated)
    private var pending = false // main thread
    private let reader: () -> MediaTargetAvailability
    private let timeout: TimeInterval
    private static let framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY | RTLD_LOCAL)
    init(reader: @escaping () -> MediaTargetAvailability = SystemMediaTarget.read, timeout: TimeInterval = 0.75) {
        self.reader = reader; self.timeout = timeout
    }
    func query(_ completion: @escaping (MediaTargetAvailability) -> Void) {
        guard !pending else { completion(.unknown); return }
        pending = true
        var delivered = false // callbacks serialized on main
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            guard !delivered else { return }
            delivered = true; completion(.unknown)
        }
        let read = reader
        worker.async { [weak self] in
            let result = read()
            DispatchQueue.main.async {
                self?.pending = false
                guard !delivered else { return }
                delivered = true; completion(result)
            }
        }
    }
    private static func read() -> MediaTargetAvailability {
        guard framework != nil, let type = NSClassFromString("MRNowPlayingRequest") as? NSObject.Type else { return .unknown }
        let pathSelector = NSSelectorFromString("localNowPlayingPlayerPath")
        guard let method = class_getClassMethod(type, pathSelector),
              method_getNumberOfArguments(method) == 2, objectReturn(method),
              let path = type.perform(pathSelector)?.takeUnretainedValue() as? NSObject else { return .unknown }
        let clientSelector = NSSelectorFromString("client")
        guard let clientMethod = class_getInstanceMethod(Swift.type(of: path), clientSelector),
              method_getNumberOfArguments(clientMethod) == 2, objectReturn(clientMethod) else { return .unknown }
        guard let client = path.perform(clientSelector)?.takeUnretainedValue() as? NSObject else { return .none }
        let pidSelector = NSSelectorFromString("processIdentifier")
        guard let pidMethod = class_getInstanceMethod(Swift.type(of: client), pidSelector),
              method_getNumberOfArguments(pidMethod) == 2 else { return .unknown }
        let encoding = method_copyReturnType(pidMethod)
        defer { free(encoding) }
        guard String(cString: encoding) == "i" else { return .unknown }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Int32
        let getter = unsafeBitCast(method_getImplementation(pidMethod), to: Getter.self)
        let pid = getter(client, pidSelector)
        guard pid > 0 else { return .unknown }
        // A paused, still-running target remains resumable. Do not infer idle
        // from silence or a zero playback rate and steal its Play command.
        return NSRunningApplication(processIdentifier: pid).map { $0.isTerminated ? .none : .available } ?? .none
    }
    private static func objectReturn(_ method: Method) -> Bool {
        let encoding = method_copyReturnType(method)
        defer { free(encoding) }
        return String(cString: encoding) == "@"
    }
}
