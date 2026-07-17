import Foundation
import SwiftData

@Model
final class PendingChangeEntity {
    @Attribute(.unique) var id: String
    var listingID: String
    var kindRaw: String
    var payload: Data
    var queuedAt: Date
    var attemptCount: Int
    var lastError: String?

    init(
        id: String,
        listingID: String,
        kindRaw: String,
        payload: Data,
        queuedAt: Date,
        attemptCount: Int,
        lastError: String?
    ) {
        self.id = id
        self.listingID = listingID
        self.kindRaw = kindRaw
        self.payload = payload
        self.queuedAt = queuedAt
        self.attemptCount = attemptCount
        self.lastError = lastError
    }
}
