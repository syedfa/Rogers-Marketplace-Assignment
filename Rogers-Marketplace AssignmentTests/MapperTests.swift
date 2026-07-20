import Testing
import Foundation
@testable import Rogers_Marketplace_Assignment

@Suite("Mappers")
struct MapperTests {
    @Test("Listing -> ListingEntity -> Listing round-trips every field")
    func entityRoundTrip() {
        let original = TestFixtures.listing(
            title: "Standing Desk",
            description: "Electric height adjustment.",
            price: Decimal(string: "349.99")!,
            category: .furniture,
            imageURLs: ["https://example.com/a.jpg", "data:image/jpeg;base64,Zm9v"],
            isFavorite: true,
            syncState: .pendingUpdate,
            locallyEditedFields: [Listing.Field.title, Listing.Field.price]
        )

        let entity = ListingEntity(listing: original)
        let roundTripped = Listing(entity: entity)

        #expect(roundTripped == original)
    }

    @Test("Entity mapper preserves Decimal price precision")
    func preservesDecimalPrecision() {
        let precisePrice = Decimal(string: "19.995")!
        let original = TestFixtures.listing(price: precisePrice)

        let entity = ListingEntity(listing: original)
        let roundTripped = Listing(entity: entity)

        #expect(roundTripped.price == precisePrice)
    }

    @Test("update(from:) mutates an existing entity in place rather than replacing it")
    func updateMutatesInPlace() {
        let original = TestFixtures.listing(title: "Old Title")
        let entity = ListingEntity(listing: original)
        let objectIdentifier = ObjectIdentifier(entity)

        var updated = original
        updated.title = "New Title"
        updated.updatedAt = Date(timeIntervalSince1970: 9_999_999)
        entity.update(from: updated)

        #expect(ObjectIdentifier(entity) == objectIdentifier)
        #expect(entity.title == "New Title")
        #expect(Listing(entity: entity).updatedAt == updated.updatedAt)
    }

    @Test("Listing <-> ListingRecord round-trips the fields JSON Server understands")
    func recordRoundTrip() {
        let original = TestFixtures.listing(
            id: "abc-123",
            title: "Vintage Bicycle",
            description: "Barely used.",
            price: Decimal(string: "120.50")!,
            category: .sports,
            imageURLs: ["https://example.com/a.jpg"]
        )

        let record = ListingRecord(listing: original)
        let roundTripped = record.asListing()

        #expect(roundTripped.id == original.id)
        #expect(roundTripped.title == original.title)
        #expect(roundTripped.description == original.description)
        #expect(roundTripped.price == original.price)
        #expect(roundTripped.category == original.category)
        #expect(roundTripped.imageURLs == original.imageURLs)
        // Local-only fields are not part of the wire format.
        #expect(roundTripped.isFavorite == false)
        #expect(roundTripped.syncState == .synced)
        #expect(roundTripped.locallyEditedFields.isEmpty)
    }

    @Test("ListingRecord encodes to and decodes from JSON without loss")
    func recordJSONCodable() throws {
        let original = TestFixtures.listing(price: Decimal(string: "42.42")!)
        let record = ListingRecord(listing: original)

        let data = try JSONEncoder.marketplace.encode(record)
        let decoded = try JSONDecoder.marketplace.decode(ListingRecord.self, from: data)

        #expect(decoded.asListing().price == original.price)
        #expect(decoded.id == original.id)
    }
}
