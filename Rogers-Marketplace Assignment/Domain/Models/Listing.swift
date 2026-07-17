import Foundation

/// Domain representation of a marketplace listing. Plain, Sendable, Codable
/// value type — never a SwiftData `@Model`. Presentation and Domain code
/// only ever see `Listing`; `Data/Persistence` maps to/from `ListingEntity`.
struct Listing: Identifiable, Equatable, Hashable, Codable, Sendable {
    var id: String
    var title: String
    var description: String
    var price: Decimal
    var category: Category
    var imageURLs: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var syncState: ListingSyncState
    /// Field names the user edited locally since the last successful sync.
    /// Drives the field-merge conflict strategy.
    var locallyEditedFields: Set<String>

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String,
        price: Decimal,
        category: Category,
        imageURLs: [String] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncState: ListingSyncState = .synced,
        locallyEditedFields: Set<String> = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.price = price
        self.category = category
        self.imageURLs = imageURLs
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncState = syncState
        self.locallyEditedFields = locallyEditedFields
    }
}

extension Listing {
    /// Field name constants shared by the validator, the field-merge
    /// resolver, and the outbox snapshot — avoids stringly-typed drift.
    enum Field {
        static let title = "title"
        static let description = "description"
        static let price = "price"
        static let category = "category"
        static let imageURLs = "imageURLs"
    }
}
