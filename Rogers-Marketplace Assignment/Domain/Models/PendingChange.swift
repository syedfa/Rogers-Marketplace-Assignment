import Foundation

/// A queued offline write, persisted in the SwiftData outbox and drained
/// FIFO by `SyncEngine` once connectivity returns.
struct PendingChange: Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case create
        case update
    }

    var id: String
    var listingID: String
    var kind: Kind
    var snapshot: Listing
    var queuedAt: Date
    var attemptCount: Int
    var lastError: String?

    init(
        id: String = UUID().uuidString,
        listingID: String,
        kind: Kind,
        snapshot: Listing,
        queuedAt: Date = Date(),
        attemptCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.listingID = listingID
        self.kind = kind
        self.snapshot = snapshot
        self.queuedAt = queuedAt
        self.attemptCount = attemptCount
        self.lastError = lastError
    }
}
