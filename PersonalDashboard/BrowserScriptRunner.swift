import AppKit

/// Revokes queued close work when the user disables the cat or its trip ends.
final class BrowserRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
}

/// Apple events are blocking. Share one serial worker between tracking and the
/// cat so an unresponsive browser cannot block drawing or overlap other scans.
final class BrowserScriptRunner: @unchecked Sendable {
    static let shared = BrowserScriptRunner()
    private let queue = DispatchQueue(label: "PersonalDashboard.browser", qos: .utility)

    func perform<T: Sendable>(_ operation: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = autoreleasepool(invoking: operation)
                continuation.resume(returning: result)
            }
        }
    }

    static func execute(_ source: String) -> String? {
        var error: NSDictionary?
        let bounded = "with timeout of 2 seconds\n\(source)\nend timeout"
        let value = NSAppleScript(source: bounded)?.executeAndReturnError(&error).stringValue
        return error == nil ? value : nil
    }
}
