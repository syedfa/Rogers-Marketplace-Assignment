import Foundation

/// User-selectable conflict resolution strategy, persisted via
/// `@AppStorage` from the Settings screen.
enum MergeStrategy: String, CaseIterable, Codable, Sendable, Identifiable {
    case lastWriteWins
    case fieldMerge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lastWriteWins: return "Last Write Wins"
        case .fieldMerge: return "Merge Fields"
        }
    }

    var explanation: String {
        switch self {
        case .lastWriteWins:
            return "When the same listing changed on this device and on the server, keep whichever version was updated most recently."
        case .fieldMerge:
            return "When the same listing changed in both places, keep your locally edited fields and take the server's values for everything else."
        }
    }
}
