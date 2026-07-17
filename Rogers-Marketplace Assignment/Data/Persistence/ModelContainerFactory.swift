import Foundation
import SwiftData

enum ModelContainerFactory {
    static let schema = Schema([ListingEntity.self, PendingChangeEntity.self])

    /// The app's real, disk-backed container.
    static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// An isolated, in-memory container for unit tests and SwiftUI previews.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
