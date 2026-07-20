import Foundation
@testable import Rogers_Marketplace_Assignment

/// Test double for `APIClientProtocol`. Not thread-safe by design — each
/// test owns a single instance and drives it from one Task, which is the
/// pattern Swift Testing encourages.
final class FakeAPIClient: APIClientProtocol, @unchecked Sendable {
    var listingsToReturn: [Listing] = []
    var createHandler: (@Sendable (Listing) async throws -> Listing)?
    var updateHandler: (@Sendable (Listing) async throws -> Listing)?
    private(set) var createdListings: [Listing] = []
    private(set) var updatedListings: [Listing] = []
    private(set) var fetchCallCount = 0

    func fetchListings() async throws -> [Listing] {
        fetchCallCount += 1
        return listingsToReturn
    }

    func createListing(_ listing: Listing) async throws -> Listing {
        createdListings.append(listing)
        if let handler = createHandler { return try await handler(listing) }
        return listing
    }

    func updateListing(_ listing: Listing) async throws -> Listing {
        updatedListings.append(listing)
        if let handler = updateHandler { return try await handler(listing) }
        return listing
    }
}

/// Test double for `ConnectivityMonitoring` with a settable, broadcastable
/// connection state.
final class FakeConnectivityMonitor: ConnectivityMonitoring, @unchecked Sendable {
    private var connected: Bool
    private var continuations: [AsyncStream<Bool>.Continuation] = []

    init(initiallyConnected: Bool = true) {
        connected = initiallyConnected
    }

    var isConnected: Bool {
        get async { connected }
    }

    func statusStream() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            continuation.yield(connected)
            continuations.append(continuation)
        }
    }

    func setConnected(_ value: Bool) {
        connected = value
        for continuation in continuations {
            continuation.yield(value)
        }
    }
}

enum TestFixtures {
    static func listing(
        id: String = UUID().uuidString,
        title: String = "Vintage Bicycle",
        description: String = "Barely used, great condition.",
        price: Decimal = 120,
        category: Rogers_Marketplace_Assignment.Category = .sports,
        imageURLs: [String] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        syncState: ListingSyncState = .synced,
        locallyEditedFields: Set<String> = []
    ) -> Listing {
        Listing(
            id: id,
            title: title,
            description: description,
            price: price,
            category: category,
            imageURLs: imageURLs,
            isFavorite: isFavorite,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncState: syncState,
            locallyEditedFields: locallyEditedFields
        )
    }
}
