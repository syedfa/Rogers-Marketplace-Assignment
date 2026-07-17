import Foundation
import BackgroundTasks

/// Registers and schedules the `BGProcessingTask` that drains the sync
/// outbox after the app is backgrounded and connectivity returns. See
/// sequence diagram 4 in `docs/ARCHITECTURE.md`.
///
/// `BGProcessingTask` launches are opportunistic and scheduled by the OS —
/// they rarely fire on the Simulator. Force one from Xcode's debugger
/// console while the app is backgrounded:
/// `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"ca.cybermedia.RogersMarketplace.sync"]`
final class BackgroundTaskCoordinator: @unchecked Sendable {
    static let taskIdentifier = "ca.cybermedia.RogersMarketplace.sync"

    private let syncEngine: SyncEngineProtocol

    init(syncEngine: SyncEngineProtocol) {
        self.syncEngine = syncEngine
    }

    /// Must be called before `applicationDidFinishLaunching` returns.
    func registerTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(processingTask)
        }
    }

    /// Call when the app resigns active with outstanding local changes, so
    /// the outbox keeps draining even if the user leaves the app.
    func scheduleSync() {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        // Best-effort: the OS may reject this if one is already queued, or
        // (commonly, on the Simulator) may simply never launch it.
        // Foreground sync on relaunch is the fallback path either way.
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(_ task: BGProcessingTask) {
        let syncTask = Task {
            await syncEngine.syncNow()
            scheduleSync() // opportunistically queue the next cycle
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            syncTask.cancel()
        }
    }
}
