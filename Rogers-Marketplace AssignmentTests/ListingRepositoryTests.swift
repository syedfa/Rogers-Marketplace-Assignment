import Testing
import Foundation
import SwiftData
@testable import Rogers_Marketplace_Assignment

@Suite("ListingRepository")
struct ListingRepositoryTests {
    func makeRepository() throws -> ListingRepository {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        return ListingRepository(modelContainer: container)
    }

    @Test("Creating a listing persists it and queues a matching outbox entry")
    func createQueuesOutboxEntry() async throws {
        let repo = try makeRepository()
        let listing = TestFixtures.listing(title: "Standing Desk")

        try await repo.create(listing)

        let fetched = try await repo.fetchListing(id: listing.id)
        #expect(fetched?.title == "Standing Desk")
        #expect(fetched?.syncState == .pendingCreate)

        let pending = try await repo.pendingChanges()
        #expect(pending.count == 1)
        #expect(pending[0].kind == .create)
        #expect(pending[0].listingID == listing.id)
    }

    @Test("Updating a listing queues an update outbox entry with the edited fields")
    func updateQueuesOutboxEntry() async throws {
        let repo = try makeRepository()
        let listing = TestFixtures.listing(title: "Old Title", syncState: .synced)
        try await repo.create(listing)
        try await repo.markSynced(listingID: listing.id, resolved: listing)

        var edited = listing
        edited.title = "New Title"
        try await repo.update(edited, editedFields: [Listing.Field.title])

        let fetched = try await repo.fetchListing(id: listing.id)
        #expect(fetched?.title == "New Title")
        #expect(fetched?.syncState == .pendingUpdate)

        let pending = try await repo.pendingChanges()
        #expect(pending.count == 1)
        #expect(pending[0].kind == .update)
        #expect(pending[0].snapshot.locallyEditedFields == [Listing.Field.title])
    }

    @Test("Repeated edits before a sync replace the queued outbox entry rather than piling up")
    func repeatedEditsCoalesce() async throws {
        let repo = try makeRepository()
        let listing = TestFixtures.listing(title: "Old Title")
        try await repo.create(listing)
        try await repo.markSynced(listingID: listing.id, resolved: listing)

        var firstEdit = listing
        firstEdit.title = "First Edit"
        try await repo.update(firstEdit, editedFields: [Listing.Field.title])

        var secondEdit = listing
        secondEdit.title = "Second Edit"
        try await repo.update(secondEdit, editedFields: [Listing.Field.title])

        let pending = try await repo.pendingChanges()
        #expect(pending.count == 1)
        #expect(pending[0].snapshot.title == "Second Edit")
    }

    @Test("Toggling favorite does not enqueue a sync — favorites are local-only")
    func favoriteDoesNotEnqueueSync() async throws {
        let repo = try makeRepository()
        let listing = TestFixtures.listing()
        try await repo.create(listing)
        try await repo.markSynced(listingID: listing.id, resolved: listing)

        try await repo.setFavorite(id: listing.id, isFavorite: true)

        let fetched = try await repo.fetchListing(id: listing.id)
        #expect(fetched?.isFavorite == true)
        #expect(fetched?.syncState == .synced)
        let pending = try await repo.pendingChanges()
        #expect(pending.isEmpty)
    }

    @Test("fetchListings filters by category")
    func fetchFiltersByCategory() async throws {
        let repo = try makeRepository()
        try await repo.create(TestFixtures.listing(id: "1", category: .electronics))
        try await repo.create(TestFixtures.listing(id: "2", category: .furniture))

        let results = try await repo.fetchListings(matching: ListingQuery(category: .furniture))

        #expect(results.count == 1)
        #expect(results[0].id == "2")
    }

    @Test("fetchListings filters by search text across title and description")
    func fetchFiltersBySearchText() async throws {
        let repo = try makeRepository()
        try await repo.create(TestFixtures.listing(id: "1", title: "Standing Desk", description: "Adjustable"))
        try await repo.create(TestFixtures.listing(id: "2", title: "Bicycle", description: "Great for standing commutes"))
        try await repo.create(TestFixtures.listing(id: "3", title: "Couch", description: "Comfortable"))

        let results = try await repo.fetchListings(matching: ListingQuery(searchText: "standing"))

        #expect(results.count == 2)
        #expect(Set(results.map(\.id)) == ["1", "2"])
    }

    @Test("fetchListings filters to favorites only")
    func fetchFiltersFavoritesOnly() async throws {
        let repo = try makeRepository()
        try await repo.create(TestFixtures.listing(id: "1"))
        try await repo.create(TestFixtures.listing(id: "2"))
        try await repo.markSynced(listingID: "1", resolved: TestFixtures.listing(id: "1"))
        try await repo.markSynced(listingID: "2", resolved: TestFixtures.listing(id: "2"))
        try await repo.setFavorite(id: "1", isFavorite: true)

        let results = try await repo.fetchListings(matching: ListingQuery(favoritesOnly: true))

        #expect(results.count == 1)
        #expect(results[0].id == "1")
    }

    @Test("upsertFromRemote inserts new listings and preserves local favorite state on existing ones")
    func upsertPreservesFavorite() async throws {
        let repo = try makeRepository()
        try await repo.create(TestFixtures.listing(id: "1", title: "Original"))
        try await repo.markSynced(listingID: "1", resolved: TestFixtures.listing(id: "1", title: "Original"))
        try await repo.setFavorite(id: "1", isFavorite: true)

        let remoteUpdate = TestFixtures.listing(id: "1", title: "Server Updated Title")
        let brandNew = TestFixtures.listing(id: "2", title: "Brand New")
        try await repo.upsertFromRemote([remoteUpdate, brandNew])

        let existing = try await repo.fetchListing(id: "1")
        #expect(existing?.title == "Server Updated Title")
        #expect(existing?.isFavorite == true)

        let created = try await repo.fetchListing(id: "2")
        #expect(created?.title == "Brand New")
    }

    @Test("recordFailure increments the attempt count and marks the listing failed")
    func recordFailureTracksAttempts() async throws {
        let repo = try makeRepository()
        let listing = TestFixtures.listing()
        try await repo.create(listing)
        let pending = try await repo.pendingChanges()
        let changeID = try #require(pending.first?.id)

        try await repo.recordFailure(pendingChangeID: changeID, error: "network timeout")

        let stillPending = try await repo.pendingChanges()
        #expect(stillPending.first?.attemptCount == 1)
        #expect(stillPending.first?.lastError == "network timeout")
        let fetched = try await repo.fetchListing(id: listing.id)
        #expect(fetched?.syncState == .failed)
    }

    @Test("removePendingChange clears the outbox entry")
    func removePendingChangeClearsOutbox() async throws {
        let repo = try makeRepository()
        try await repo.create(TestFixtures.listing())
        let pending = try await repo.pendingChanges()
        let changeID = try #require(pending.first?.id)

        try await repo.removePendingChange(id: changeID)

        let remaining = try await repo.pendingChanges()
        #expect(remaining.isEmpty)
    }
}
