import Foundation
import SwiftData

/// SwiftData-backed implementation of `ListingRepositoryProtocol`. As a
/// `@ModelActor`, every method body runs isolated to this actor's private
/// `ModelContext` — callers never touch SwiftData types directly, and no
/// `ModelContext`/`ModelObject` crosses an actor boundary.
@ModelActor
actor ListingRepository: ListingRepositoryProtocol {
    func fetchListings(matching query: ListingQuery) async throws -> [Listing] {
        let descriptor = FetchDescriptor<ListingEntity>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let all = try modelContext.fetch(descriptor)
        let searchText = query.searchText.lowercased()

        let filtered = all.filter { entity in
            if query.favoritesOnly && !entity.isFavorite { return false }
            if let category = query.category, entity.category != category.rawValue { return false }
            if !searchText.isEmpty {
                let matchesTitle = entity.title.lowercased().contains(searchText)
                let matchesDescription = entity.listingDescription.lowercased().contains(searchText)
                if !matchesTitle && !matchesDescription { return false }
            }
            return true
        }
        return filtered.map(Listing.init(entity:))
    }

    func fetchListing(id: String) async throws -> Listing? {
        try fetchEntity(id: id).map(Listing.init(entity:))
    }

    func create(_ listing: Listing) async throws {
        var pending = listing
        pending.syncState = .pendingCreate
        pending.locallyEditedFields = []
        modelContext.insert(ListingEntity(listing: pending))
        try enqueue(PendingChange(listingID: pending.id, kind: .create, snapshot: pending))
        try modelContext.save()
    }

    func update(_ listing: Listing, editedFields: Set<String>) async throws {
        guard let entity = try fetchEntity(id: listing.id) else {
            throw RepositoryError.notFound
        }
        var pending = listing
        pending.syncState = .pendingUpdate
        pending.locallyEditedFields = editedFields
        entity.update(from: pending)

        // Coalesce rapid successive edits into a single queued change instead
        // of piling up redundant outbox rows for the same listing.
        try removeExistingPendingChanges(listingID: listing.id)
        try enqueue(PendingChange(listingID: pending.id, kind: .update, snapshot: pending))
        try modelContext.save()
    }

    func setFavorite(id: String, isFavorite: Bool) async throws {
        guard let entity = try fetchEntity(id: id) else {
            throw RepositoryError.notFound
        }
        entity.isFavorite = isFavorite
        try modelContext.save()
    }

    func pendingChanges() async throws -> [PendingChange] {
        let descriptor = FetchDescriptor<PendingChangeEntity>(sortBy: [SortDescriptor(\.queuedAt, order: .forward)])
        return try modelContext.fetch(descriptor).map(PendingChange.init(entity:))
    }

    func markSynced(listingID: String, resolved: Listing) async throws {
        guard let entity = try fetchEntity(id: listingID) else { return }
        var synced = resolved
        synced.syncState = .synced
        synced.locallyEditedFields = []
        entity.update(from: synced)
        // "Synced" is a stronger claim than "this one pending change was
        // drained" — it means the listing has no outstanding local work, so
        // any queued outbox row for it (there's at most one, by
        // construction) is stale and must go with it.
        try removeExistingPendingChanges(listingID: listingID)
        try modelContext.save()
    }

    func recordFailure(pendingChangeID: String, error: String) async throws {
        let descriptor = FetchDescriptor<PendingChangeEntity>(
            predicate: #Predicate { $0.id == pendingChangeID }
        )
        guard let change = try modelContext.fetch(descriptor).first else { return }
        change.attemptCount += 1
        change.lastError = error
        if let entity = try fetchEntity(id: change.listingID) {
            entity.syncStatusRaw = ListingSyncState.failed.rawValue
        }
        try modelContext.save()
    }

    func removePendingChange(id: String) async throws {
        let descriptor = FetchDescriptor<PendingChangeEntity>(predicate: #Predicate { $0.id == id })
        guard let change = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(change)
        try modelContext.save()
    }

    func upsertFromRemote(_ listings: [Listing]) async throws {
        for remote in listings {
            if let existing = try fetchEntity(id: remote.id) {
                var merged = remote
                merged.isFavorite = existing.isFavorite
                existing.update(from: merged)
            } else {
                modelContext.insert(ListingEntity(listing: remote))
            }
        }
        try modelContext.save()
    }

    // MARK: - Helpers

    private func fetchEntity(id: String) throws -> ListingEntity? {
        let descriptor = FetchDescriptor<ListingEntity>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    private func removeExistingPendingChanges(listingID: String) throws {
        let descriptor = FetchDescriptor<PendingChangeEntity>(
            predicate: #Predicate { $0.listingID == listingID }
        )
        for change in try modelContext.fetch(descriptor) {
            modelContext.delete(change)
        }
    }

    private func enqueue(_ change: PendingChange) throws {
        modelContext.insert(PendingChangeEntity(pendingChange: change))
    }
}
