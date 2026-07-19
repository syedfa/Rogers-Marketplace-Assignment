import Foundation
import Network

/// Wraps `NWPathMonitor` behind `ConnectivityMonitoring`. An actor rather
/// than a class with manual locking — `NWPathMonitor`'s own callback queue
/// is a private serial background queue (never the main thread, per
/// Apple's guidance), so updates hop into the actor with a `Task` instead
/// of a lock.
actor ConnectivityMonitor: ConnectivityMonitoring {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ca.cybermedia.RogersMarketplace.connectivity")
    private var latestStatus: Bool
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init() {
        latestStatus = monitor.currentPath.status == .satisfied
        monitor.start(queue: queue)
        monitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            Task { await self?.handleUpdate(isSatisfied: isSatisfied) }
        }
    }

    deinit {
        monitor.cancel()
    }

    var isConnected: Bool {
        latestStatus
    }

    func statusStream() -> AsyncStream<Bool> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.yield(latestStatus)
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func handleUpdate(isSatisfied: Bool) {
        latestStatus = isSatisfied
        for continuation in continuations.values {
            continuation.yield(isSatisfied)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
