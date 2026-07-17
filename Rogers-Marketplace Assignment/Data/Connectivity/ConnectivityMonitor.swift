import Foundation
import Network

/// Wraps `NWPathMonitor` behind `ConnectivityMonitoring`. The monitor's own
/// callback queue is a private serial background queue — never the main
/// thread — per Apple's guidance for `NWPathMonitor`.
final class ConnectivityMonitor: ConnectivityMonitoring, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ca.cybermedia.RogersMarketplace.connectivity")
    private let lock = NSLock()
    private var latestStatus: Bool
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init() {
        latestStatus = monitor.currentPath.status == .satisfied
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handleUpdate(isSatisfied: path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    var isConnected: Bool {
        get async {
            lock.lock()
            defer { lock.unlock() }
            return latestStatus
        }
    }

    func statusStream() -> AsyncStream<Bool> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.lock()
            continuation.yield(latestStatus)
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id)
            }
        }
    }

    private func handleUpdate(isSatisfied: Bool) {
        lock.lock()
        latestStatus = isSatisfied
        let currentContinuations = continuations
        lock.unlock()
        for continuation in currentContinuations.values {
            continuation.yield(isSatisfied)
        }
    }

    private func removeContinuation(_ id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}
