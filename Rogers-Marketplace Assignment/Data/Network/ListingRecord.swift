import Foundation

/// Wire format for JSON Server's `/listings` resource. Deliberately
/// narrower than `Listing`: `isFavorite`, `syncState`, and
/// `locallyEditedFields` are client-only concerns and never leave the
/// device.
struct ListingRecord: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var description: String
    var price: Decimal
    var category: String
    var imageURLs: [String]
    var createdAt: Date
    var updatedAt: Date

    init(listing: Listing) {
        id = listing.id
        title = listing.title
        description = listing.description
        price = listing.price
        category = listing.category.rawValue
        imageURLs = listing.imageURLs
        createdAt = listing.createdAt
        updatedAt = listing.updatedAt
    }

    func asListing() -> Listing {
        Listing(
            id: id,
            title: title,
            description: description,
            price: price,
            category: Category(rawValue: category) ?? .other,
            imageURLs: imageURLs,
            isFavorite: false,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncState: .synced,
            locallyEditedFields: []
        )
    }
}
