import Foundation

/// Resolves a conflict between a locally-edited listing (not yet
/// acknowledged by the server) and the version the server returned on pull.
/// Pure function of its inputs — no I/O, no shared state — so it is trivial
/// to unit test exhaustively.
struct ConflictResolver: Sendable {
    /// - Parameters:
    ///   - local: the on-device version, including `locallyEditedFields`.
    ///   - remote: the version returned by the server.
    ///   - strategy: user-selected resolution strategy from Settings.
    /// - Returns: the listing to persist, and whether local edits still
    ///   need to be re-pushed (true for field-merge, since the merge result
    ///   may still differ from the server).
    func resolve(
        local: Listing,
        remote: Listing,
        strategy: MergeStrategy
    ) -> (resolved: Listing, needsRepush: Bool) {
        switch strategy {
        case .lastWriteWins:
            if local.updatedAt > remote.updatedAt {
                var winner = local
                winner.syncState = .synced
                winner.locallyEditedFields = []
                return (winner, false)
            } else {
                var winner = remote
                winner.isFavorite = local.isFavorite // favorites are always local-only
                winner.syncState = .synced
                winner.locallyEditedFields = []
                return (winner, false)
            }

        case .fieldMerge:
            guard !local.locallyEditedFields.isEmpty else {
                var winner = remote
                winner.isFavorite = local.isFavorite
                winner.syncState = .synced
                return (winner, false)
            }

            var merged = remote
            merged.isFavorite = local.isFavorite
            for field in local.locallyEditedFields {
                switch field {
                case Listing.Field.title: merged.title = local.title
                case Listing.Field.description: merged.description = local.description
                case Listing.Field.price: merged.price = local.price
                case Listing.Field.category: merged.category = local.category
                case Listing.Field.imageURLs: merged.imageURLs = local.imageURLs
                default: break
                }
            }
            merged.updatedAt = Date()
            merged.syncState = .pendingUpdate
            merged.locallyEditedFields = local.locallyEditedFields
            return (merged, true)
        }
    }
}
