import Testing
import Foundation
@testable import Rogers_Marketplace_Assignment

@Suite("ConflictResolver")
struct ConflictResolverTests {
    let resolver = ConflictResolver()

    @Test("LWW picks local when local is newer")
    func lwwLocalNewer() {
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)
        let local = TestFixtures.listing(title: "Local Title", updatedAt: newer, locallyEditedFields: [Listing.Field.title])
        let remote = TestFixtures.listing(title: "Remote Title", updatedAt: older)

        let (resolved, needsRepush) = resolver.resolve(local: local, remote: remote, strategy: .lastWriteWins)

        #expect(resolved.title == "Local Title")
        #expect(resolved.syncState == .synced)
        #expect(resolved.locallyEditedFields.isEmpty)
        #expect(needsRepush == false)
    }

    @Test("LWW picks remote when remote is newer")
    func lwwRemoteNewer() {
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)
        let local = TestFixtures.listing(title: "Local Title", updatedAt: older, locallyEditedFields: [Listing.Field.title])
        let remote = TestFixtures.listing(title: "Remote Title", updatedAt: newer)

        let (resolved, needsRepush) = resolver.resolve(local: local, remote: remote, strategy: .lastWriteWins)

        #expect(resolved.title == "Remote Title")
        #expect(needsRepush == false)
    }

    @Test("LWW tie goes to remote")
    func lwwTieGoesToRemote() {
        let same = Date(timeIntervalSince1970: 1500)
        let local = TestFixtures.listing(title: "Local Title", updatedAt: same, locallyEditedFields: [Listing.Field.title])
        let remote = TestFixtures.listing(title: "Remote Title", updatedAt: same)

        let (resolved, _) = resolver.resolve(local: local, remote: remote, strategy: .lastWriteWins)

        #expect(resolved.title == "Remote Title")
    }

    @Test("LWW always preserves the local favorite flag, since favorites are local-only")
    func lwwPreservesFavorite() {
        let local = TestFixtures.listing(isFavorite: true, updatedAt: Date(timeIntervalSince1970: 1000))
        let remote = TestFixtures.listing(isFavorite: false, updatedAt: Date(timeIntervalSince1970: 2000))

        let (resolved, _) = resolver.resolve(local: local, remote: remote, strategy: .lastWriteWins)

        #expect(resolved.isFavorite == true)
    }

    @Test("Field-merge keeps locally-edited fields and takes remote for the rest")
    func fieldMergeKeepsEditedFields() {
        let local = TestFixtures.listing(
            title: "My New Title",
            description: "Original description",
            price: 50,
            locallyEditedFields: [Listing.Field.title]
        )
        let remote = TestFixtures.listing(
            title: "Someone Else's Title",
            description: "Server-updated description",
            price: 75
        )

        let (resolved, needsRepush) = resolver.resolve(local: local, remote: remote, strategy: .fieldMerge)

        #expect(resolved.title == "My New Title")
        #expect(resolved.description == "Server-updated description")
        #expect(resolved.price == 75)
        #expect(needsRepush == true)
        #expect(resolved.syncState == .pendingUpdate)
    }

    @Test("Field-merge with no locally-edited fields is equivalent to server-wins")
    func fieldMergeEmptyEditSetIsServerWins() {
        let local = TestFixtures.listing(title: "Local Title", locallyEditedFields: [])
        let remote = TestFixtures.listing(title: "Remote Title")

        let (resolved, needsRepush) = resolver.resolve(local: local, remote: remote, strategy: .fieldMerge)

        #expect(resolved.title == "Remote Title")
        #expect(needsRepush == false)
        #expect(resolved.syncState == .synced)
    }

    @Test("Field-merge keeps multiple edited fields simultaneously")
    func fieldMergeMultipleFields() {
        let local = TestFixtures.listing(
            title: "New Title",
            price: 99,
            category: .electronics,
            locallyEditedFields: [Listing.Field.title, Listing.Field.price]
        )
        let remote = TestFixtures.listing(title: "Remote Title", price: 10, category: .furniture)

        let (resolved, _) = resolver.resolve(local: local, remote: remote, strategy: .fieldMerge)

        #expect(resolved.title == "New Title")
        #expect(resolved.price == 99)
        #expect(resolved.category == .furniture) // not locally edited -> remote wins
    }

    @Test("Field-merge always preserves the local favorite flag")
    func fieldMergePreservesFavorite() {
        let local = TestFixtures.listing(isFavorite: true, locallyEditedFields: [Listing.Field.title])
        let remote = TestFixtures.listing(isFavorite: false)

        let (resolved, _) = resolver.resolve(local: local, remote: remote, strategy: .fieldMerge)

        #expect(resolved.isFavorite == true)
    }
}
