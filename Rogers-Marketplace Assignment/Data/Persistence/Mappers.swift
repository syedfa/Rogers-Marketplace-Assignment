import Foundation

extension Listing {
    init(entity: ListingEntity) {
        self.init(
            id: entity.id,
            title: entity.title,
            description: entity.listingDescription,
            price: entity.price,
            category: Category(rawValue: entity.category) ?? .other,
            imageURLs: entity.imageURLs,
            isFavorite: entity.isFavorite,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            syncState: ListingSyncState(rawValue: entity.syncStatusRaw) ?? .synced,
            locallyEditedFields: Set(entity.locallyEditedFields)
        )
    }
}

extension ListingEntity {
    convenience init(listing: Listing) {
        self.init(
            id: listing.id,
            title: listing.title,
            listingDescription: listing.description,
            price: listing.price,
            category: listing.category.rawValue,
            imageURLs: listing.imageURLs,
            isFavorite: listing.isFavorite,
            createdAt: listing.createdAt,
            updatedAt: listing.updatedAt,
            syncStatusRaw: listing.syncState.rawValue,
            locallyEditedFields: Array(listing.locallyEditedFields)
        )
    }

    /// Mutates every field in place so SwiftData tracks a single logical
    /// object across edits instead of churning through insert/delete pairs.
    func update(from listing: Listing) {
        title = listing.title
        listingDescription = listing.description
        price = listing.price
        category = listing.category.rawValue
        imageURLs = listing.imageURLs
        isFavorite = listing.isFavorite
        createdAt = listing.createdAt
        updatedAt = listing.updatedAt
        syncStatusRaw = listing.syncState.rawValue
        locallyEditedFields = Array(listing.locallyEditedFields)
    }
}

extension PendingChange {
    init(entity: PendingChangeEntity) {
        let snapshot = (try? JSONDecoder.marketplace.decode(Listing.self, from: entity.payload)) ?? CorruptedPayloadFallback.empty
        self.init(
            id: entity.id,
            listingID: entity.listingID,
            kind: Kind(rawValue: entity.kindRaw) ?? .update,
            snapshot: snapshot,
            queuedAt: entity.queuedAt,
            attemptCount: entity.attemptCount,
            lastError: entity.lastError
        )
    }
}

extension PendingChangeEntity {
    convenience init(pendingChange: PendingChange) {
        let payload = (try? JSONEncoder.marketplace.encode(pendingChange.snapshot)) ?? Data()
        self.init(
            id: pendingChange.id,
            listingID: pendingChange.listingID,
            kindRaw: pendingChange.kind.rawValue,
            payload: payload,
            queuedAt: pendingChange.queuedAt,
            attemptCount: pendingChange.attemptCount,
            lastError: pendingChange.lastError
        )
    }
}

/// A well-formed but unmistakably-invalid placeholder used only if a
/// persisted pending-change payload somehow fails to decode (e.g. corrupted
/// store); keeps the mapper total instead of force-unwrapping.
private enum CorruptedPayloadFallback {
    static let empty = Listing(
        id: "corrupted-pending-change",
        title: "",
        description: "",
        price: 0,
        category: .other
    )
}
