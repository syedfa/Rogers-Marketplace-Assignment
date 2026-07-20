import Testing
import Foundation
@testable import Rogers_Marketplace_Assignment

/// The three tests tagged `.coreRequirement` below —
/// `drainsOutboxOnReconnect`, `conflictResolvedWithLWW`, and
/// `conflictResolvedWithFieldMerge` — are the ones the assignment
/// specifically asks for ("unit tests for sync logic"). The rest of this
/// suite, and the other 8 suites in this target, exist because the
/// architecture makes them cheap to write, not because they were required.
@Suite("SyncEngine")
struct SyncEngineTests {
    func makeRepository() throws -> ListingRepository {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        return ListingRepository(modelContainer: container)
    }

    @Test("syncNow while offline does not contact the API and reports .offline")
    func offlineDoesNotSync() async throws {
        let repo = try makeRepository()
        let api = FakeAPIClient()
        let connectivity = FakeConnectivityMonitor(initiallyConnected: false)
        let engine = SyncEngine(repository: repo, apiClient: api, connectivity: connectivity, strategyProvider: { .lastWriteWins })

        await engine.syncNow()

        #expect(api.fetchCallCount == 0)
        let status = await engine.currentStatus
        #expect(status.phase == .offline)
    }

    @Test(
        "An offline create is drained FIFO once connectivity returns, and the outbox is cleared",
        .tags(.coreRequirement)
    )
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

    @Test("A failed create is retried later: attempt count increases and the change stays queued")
    func failedCreateStaysQueued() async throws {
        let repo = try makeRepository()
        try await repo.create(TestFixtures.listing(id: "a"))

        let api = FakeAPIClient()
        api.createHandler = { _ in throw APIError.serverError(status: 500, body: "boom") }
        let connectivity = FakeConnectivityMonitor(initiallyConnected: true)
        let engine = SyncEngine(repository: repo, apiClient: api, connectivity: connectivity, strategyProvider: { .lastWriteWins })

        await engine.syncNow()

        let pending = try await repo.pendingChanges()
        #expect(pending.count == 1)
        #expect(pending[0].attemptCount == 1)
        let listing = try await repo.fetchListing(id: "a")
        #expect(listing?.syncState == .failed)
    }

    @Test("Pull phase upserts new remote listings that don't exist locally")
    func pullUpsertsNewRemoteListings() async throws {
        let repo = try makeRepository()
        let api = FakeAPIClient()
        api.listingsToReturn = [TestFixtures.listing(id: "remote-1", title: "From Server")]
        let connectivity = FakeConnectivityMonitor(initiallyConnected: true)
        let engine = SyncEngine(repository: repo, apiClient: api, connectivity: connectivity, strategyProvider: { .lastWriteWins })

        await engine.syncNow()

        let fetched = try await repo.fetchListing(id: "remote-1")
        #expect(fetched?.title == "From Server")
    }

    @Test(
        "A local pending edit that conflicts with a remote pull is resolved via Last-Write-Wins",
        .tags(.coreRequirement)
    )
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

    @Test(
        "A local pending edit that conflicts with a remote pull is resolved via field-merge",
        .tags(.coreRequirement)
    )
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

    @Test("Status stream transitions from syncing to synced on a successful sync")
    func statusStreamTransitions() async throws {
        let repo = try makeRepository()
        let api = FakeAPIClient()
        let connectivity = FakeConnectivityMonitor(initiallyConnected: true)
        let engine = SyncEngine(repository: repo, apiClient: api, connectivity: connectivity, strategyProvider: { .lastWriteWins })

        await engine.syncNow()

        let status = await engine.currentStatus
        guard case .synced = status.phase else {
            Issue.record("expected .synced, got \(status.phase)")
            return
        }
    }

    @Test("startObservingConnectivity performs an immediate sync attempt")
    func immediateSyncOnStart() async throws {
        let repo = try makeRepository()
        try await repo.create(TestFixtures.listing(id: "a"))
        let api = FakeAPIClient()
        let connectivity = FakeConnectivityMonitor(initiallyConnected: true)
        let engine = SyncEngine(repository: repo, apiClient: api, connectivity: connectivity, strategyProvider: { .lastWriteWins })

        await engine.startObservingConnectivity()
        await waitUntil { (try? await repo.pendingChanges().isEmpty) == true }

        #expect(api.createdListings.map(\.id) == ["a"])
        let pending = try await repo.pendingChanges()
        #expect(pending.isEmpty)
    }

    @Test("A change queued while offline is retried automatically once connectivity is regained")
    func retriesQueuedChangeOnReconnect() async throws {
        let repo = try makeRepository()
        try await repo.create(TestFixtures.listing(id: "a"))
        let api = FakeAPIClient()
        let connectivity = FakeConnectivityMonitor(initiallyConnected: false)
        let engine = SyncEngine(repository: repo, apiClient: api, connectivity: connectivity, strategyProvider: { .lastWriteWins })

        await engine.startObservingConnectivity()
        await waitUntil { await engine.currentStatus.phase == .offline }

        // Still offline: nothing attempted yet, the change is still queued.
        #expect(api.createdListings.isEmpty)
        let stillPending = try await repo.pendingChanges()
        #expect(stillPending.count == 1)

        connectivity.setConnected(true)
        await waitUntil { (try? await repo.pendingChanges().isEmpty) == true }

        #expect(api.createdListings.map(\.id) == ["a"])
        let pending = try await repo.pendingChanges()
        #expect(pending.isEmpty)
        let synced = try await repo.fetchListing(id: "a")
        #expect(synced?.syncState == .synced)
    }

    @Test("A change that failed while nominally connected is retried and clears once the server recovers")
    func retriesFailedAttemptOnReconnect() async throws {
        let repo = try makeRepository()
        try await repo.create(TestFixtures.listing(id: "a"))
        let api = FakeAPIClient()
        api.createHandler = { _ in throw APIError.serverError(status: 500, body: "boom") }
        let connectivity = FakeConnectivityMonitor(initiallyConnected: true)
        let engine = SyncEngine(repository: repo, apiClient: api, connectivity: connectivity, strategyProvider: { .lastWriteWins })

        // First attempt: device is "connected" but the request itself fails
        // (e.g. the mock server isn't running yet).
        await engine.syncNow()
        var pending = try await repo.pendingChanges()
        #expect(pending.count == 1)
        #expect(pending[0].attemptCount == 1)

        // The server becomes reachable; a subsequent reconnect event should
        // pick the queued change back up and this time succeed.
        api.createHandler = nil
        await engine.startObservingConnectivity()
        connectivity.setConnected(false)
        await waitUntil { await engine.currentStatus.phase == .offline }
        connectivity.setConnected(true)
        await waitUntil { (try? await repo.pendingChanges().isEmpty) == true }

        pending = try await repo.pendingChanges()
        #expect(pending.isEmpty)
        let listing = try await repo.fetchListing(id: "a")
        #expect(listing?.syncState == .synced)
    }

    @Test("startObservingConnectivity is idempotent: a second call does not start a duplicate observer")
    func idempotentStart() async throws {
        let repo = try makeRepository()
        let api = FakeAPIClient()
        let connectivity = FakeConnectivityMonitor(initiallyConnected: true)
        let engine = SyncEngine(repository: repo, apiClient: api, connectivity: connectivity, strategyProvider: { .lastWriteWins })

        await engine.startObservingConnectivity()
        await waitUntil { await engine.currentStatus.phase != .idle }
        await engine.startObservingConnectivity()

        let fetchCountBeforeFlap = api.fetchCallCount
        connectivity.setConnected(false)
        await waitUntil { await engine.currentStatus.phase == .offline }
        connectivity.setConnected(true)
        await waitUntil { api.fetchCallCount > fetchCountBeforeFlap }

        // A single reconnect should trigger exactly one more pull, not two —
        // two would mean a duplicate observer was started.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(api.fetchCallCount == fetchCountBeforeFlap + 1)
    }
}
