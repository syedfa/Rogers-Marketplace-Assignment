import Foundation
import SwiftData

@Model
final class ListingEntity {
    @Attribute(.unique) var id: String
    var title: String
    var listingDescription: String
    var price: Decimal
    var category: String
    var imageURLs: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var syncStatusRaw: String
    var locallyEditedFields: [String]

    init(
        id: String,
        title: String,
        listingDescription: String,
        price: Decimal,
        category: String,
        imageURLs: [String],
        isFavorite: Bool,
        createdAt: Date,
        updatedAt: Date,
        syncStatusRaw: String,
        locallyEditedFields: [String]
    ) {
        self.id = id
        self.title = title
        self.listingDescription = listingDescription
        self.price = price
        self.category = category
        self.imageURLs = imageURLs
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStatusRaw = syncStatusRaw
        self.locallyEditedFields = locallyEditedFields
    }
}
