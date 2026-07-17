import Foundation

/// Per-listing sync state, surfaced in the UI as a badge on pending items.
enum ListingSyncState: String, Codable, Sendable, Hashable {
    case synced
    case pendingCreate
    case pendingUpdate
    case failed
}

/// App-wide sync state, driven by `SyncEngine` and observed by the
/// `SyncStatusBanner` and Settings screen.
enum SyncPhase: Equatable, Sendable {
    case idle
    case offline
    case syncing
    case synced(at: Date)
    case failed(String)
}

struct SyncStatus: Equatable, Sendable {
    var phase: SyncPhase
    var pendingCount: Int
    var resolvedConflicts: Int

    static let initial = SyncStatus(phase: .idle, pendingCount: 0, resolvedConflicts: 0)
}
