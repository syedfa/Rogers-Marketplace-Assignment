import Foundation

/// Query parameters for listing the marketplace feed.
struct ListingQuery: Equatable, Sendable {
    var searchText: String = ""
    var category: Category?
    var favoritesOnly: Bool = false
}

/// Domain-facing façade over local persistence. Implemented by
/// `Data/Repository/ListingRepository`, backed by SwiftData. ViewModels only
/// ever see this protocol, never `ListingEntity` or `ModelContext`.
protocol ListingRepositoryProtocol: Sendable {
    func fetchListings(matching query: ListingQuery) async throws -> [Listing]
    func fetchListing(id: String) async throws -> Listing?
    func create(_ listing: Listing) async throws
    func update(_ listing: Listing, editedFields: Set<String>) async throws
    func setFavorite(id: String, isFavorite: Bool) async throws
    func pendingChanges() async throws -> [PendingChange]
    func markSynced(listingID: String, resolved: Listing) async throws
    func recordFailure(pendingChangeID: String, error: String) async throws
    func removePendingChange(id: String) async throws
    func upsertFromRemote(_ listings: [Listing]) async throws
}
