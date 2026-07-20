import Testing
import Foundation
@testable import Rogers_Marketplace_Assignment

@Suite("ListingGridViewModel")
@MainActor
struct ListingGridViewModelTests {
    func makeRepository() throws -> ListingRepository {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        return ListingRepository(modelContainer: container)
    }

    @Test("applyFavoriteChange updates the listing in place on the full feed")
    func applyFavoriteChangeUpdatesInPlace() async throws {
        let repo = try makeRepository()
        let listing = TestFixtures.listing(id: "1", isFavorite: false)
        try await repo.create(listing)
        let viewModel = ListingGridViewModel(repository: repo, syncEngine: FakeSyncEngine(), favoritesOnly: false)
        viewModel.onAppear()
        await waitUntil { viewModel.listings.count == 1 }

        viewModel.applyFavoriteChange(listingID: "1", isFavorite: true)

        #expect(viewModel.listings.count == 1)
        #expect(viewModel.listings[0].isFavorite == true)
    }

    @Test("applyFavoriteChange removes the listing from a favorites-only feed when unfavorited")
    func applyFavoriteChangeRemovesFromFavoritesOnlyFeed() async throws {
        let repo = try makeRepository()
        let listing = TestFixtures.listing(id: "1", isFavorite: true)
        try await repo.create(listing)
        try await repo.markSynced(listingID: "1", resolved: listing)
        try await repo.setFavorite(id: "1", isFavorite: true)
        let viewModel = ListingGridViewModel(repository: repo, syncEngine: FakeSyncEngine(), favoritesOnly: true)
        viewModel.onAppear()
        await waitUntil { viewModel.listings.count == 1 }

        viewModel.applyFavoriteChange(listingID: "1", isFavorite: false)

        #expect(viewModel.listings.isEmpty)
    }

    @Test("applyFavoriteChange keeps the listing on the full feed even when unfavorited")
    func applyFavoriteChangeKeepsListingOnFullFeedWhenUnfavorited() async throws {
        let repo = try makeRepository()
        let listing = TestFixtures.listing(id: "1", isFavorite: true)
        try await repo.create(listing)
        let viewModel = ListingGridViewModel(repository: repo, syncEngine: FakeSyncEngine(), favoritesOnly: false)
        viewModel.onAppear()
        await waitUntil { viewModel.listings.count == 1 }

        viewModel.applyFavoriteChange(listingID: "1", isFavorite: false)

        #expect(viewModel.listings.count == 1)
        #expect(viewModel.listings[0].isFavorite == false)
    }

    @Test("applyFavoriteChange for an id not currently in the list is a no-op")
    func applyFavoriteChangeIgnoresUnknownID() async throws {
        let repo = try makeRepository()
        try await repo.create(TestFixtures.listing(id: "1"))
        let viewModel = ListingGridViewModel(repository: repo, syncEngine: FakeSyncEngine(), favoritesOnly: false)
        viewModel.onAppear()
        await waitUntil { viewModel.listings.count == 1 }

        viewModel.applyFavoriteChange(listingID: "does-not-exist", isFavorite: true)

        #expect(viewModel.listings.count == 1)
        #expect(viewModel.listings[0].isFavorite == false)
    }

    @Test("toggleFavorite persists the change and reflects it immediately, without waiting for a reload")
    func toggleFavoritePersistsAndUpdatesImmediately() async throws {
        let repo = try makeRepository()
        let listing = TestFixtures.listing(id: "1", isFavorite: false)
        try await repo.create(listing)
        let viewModel = ListingGridViewModel(repository: repo, syncEngine: FakeSyncEngine(), favoritesOnly: false)
        viewModel.onAppear()
        await waitUntil { viewModel.listings.count == 1 }

        viewModel.toggleFavorite(viewModel.listings[0])
        await waitUntil { viewModel.listings[0].isFavorite == true }

        #expect(viewModel.listings[0].isFavorite == true)
        let persisted = try await repo.fetchListing(id: "1")
        #expect(persisted?.isFavorite == true)
    }
}
