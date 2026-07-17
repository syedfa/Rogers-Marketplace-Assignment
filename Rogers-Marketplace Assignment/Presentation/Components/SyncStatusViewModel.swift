import Foundation
import Observation

@MainActor
@Observable
final class SyncStatusViewModel {
    private(set) var status: SyncStatus = .initial

    private let syncEngine: SyncEngineProtocol
    private var observationTask: Task<Void, Never>?

    init(syncEngine: SyncEngineProtocol) {
        self.syncEngine = syncEngine
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await status in await syncEngine.statusStream() {
                self.status = status
            }
        }
    }

    func syncNow() {
        Task { await syncEngine.syncNow() }
    }
}
