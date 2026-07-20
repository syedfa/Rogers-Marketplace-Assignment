import Testing
import Foundation
@testable import Rogers_Marketplace_Assignment

@Suite("SyncEngine")
struct SyncEngineTests {
    func makeRepository() throws -> ListingRepository {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        return ListingRepository(modelContainer: container)
    }

    @Test("An offline create is drained FIFO once connectivity returns, and the outbox is cleared")
    func drainsOutboxOnReconnect() async throws {
        let repo = try makeRepository()
        let listingA = TestFixtures.listing(id: "a", title: "First")
        let listingB = TestFixtures.listing(id: "b", title: "Second")
        try await repo.create(listingA)
        try await Task.sleep(nanoseconds: 2_000_000) // ensure distinct queuedAt ordering
        try await repo.create(listingB)

        let api = FakeAPIClient()
        api.listingsToReturn = [] // pull phase returns nothing new
        let connectivity = FakeConnectivityMonitor(initiallyConnected: true)
        let engine = SyncEngine(repository: repo, apiClient: api, connectivity: connectivity, strategyProvider: { .lastWriteWins })

        await engine.syncNow()

        #expect(api.createdListings.map(\.id) == ["a", "b"])
        let pending = try await repo.pendingChanges()
        #expect(pending.isEmpty)
        let synced = try await repo.fetchListing(id: "a")
        #expect(synced?.syncState == .synced)
    }

    @Test("A local pending edit that conflicts with a remote pull is resolved via Last-Write-Wins")
    func conflictResolvedWithLWW() async throws {
        let repo = try makeRepository()
        let base = TestFixtures.listing(id: "1", title: "Original", updatedAt: Date(timeIntervalSince1970: 1000))
        try await repo.create(base)
        try await repo.markSynced(listingID: "1", resolved: base)

        var localEdit = base
        localEdit.title = "Local Edit"
        localEdit.updatedAt = Date(timeIntervalSince1970: 3000) // newer than remote
        try await repo.update(localEdit, editedFields: [Listing.Field.title])

        let api = FakeAPIClient()
        var remoteVersion = base
        remoteVersion.title = "Remote Edit"
        remoteVersion.updatedAt = Date(timeIntervalSince1970: 2000) // older than local
        api.listingsToReturn = [remoteVersion]
        // Simulate the create/update calls that would happen in drainOutbox failing so the
        // pending change (and therefore the conflict) survives into the pull phase.
        api.updateHandler = { _ in throw APIError.serverError(status: 500, body: "boom") }

        let connectivity = FakeConnectivityMonitor(initiallyConnected: true)
        let engine = SyncEngine(repository: repo, apiClient: api, connectivity: connectivity, strategyProvider: { .lastWriteWins })

        await engine.syncNow()

        let resolved = try await repo.fetchListing(id: "1")
        #expect(resolved?.title == "Local Edit") // local was newer -> LWW keeps it
    }

    @Test("A local pending edit that conflicts with a remote pull is resolved via field-merge")
    func conflictResolvedWithFieldMerge() async throws {
        let repo = try makeRepository()
        let base = TestFixtures.listing(id: "1", title: "Original", description: "Original description", price: 10)
        try await repo.create(base)
        try await repo.markSynced(listingID: "1", resolved: base)

        var localEdit = base
        localEdit.title = "Local Title"
        try await repo.update(localEdit, editedFields: [Listing.Field.title])

        let api = FakeAPIClient()
        var remoteVersion = base
        remoteVersion.title = "Remote Title"
        remoteVersion.description = "Remote description"
        remoteVersion.price = 25
        api.listingsToReturn = [remoteVersion]
        api.updateHandler = { _ in throw APIError.serverError(status: 500, body: "boom") }

        let connectivity = FakeConnectivityMonitor(initiallyConnected: true)
        let engine = SyncEngine(repository: repo, apiClient: api, connectivity: connectivity, strategyProvider: { .fieldMerge })

        await engine.syncNow()

        let resolved = try await repo.fetchListing(id: "1")
        #expect(resolved?.title == "Local Title") // locally edited field kept
        #expect(resolved?.description == "Remote description") // untouched field takes remote
        #expect(resolved?.price == 25)
    }
}
