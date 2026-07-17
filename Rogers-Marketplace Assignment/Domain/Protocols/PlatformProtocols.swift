import Foundation
import CoreGraphics

/// Abstraction over `NWPathMonitor` so sync logic can be tested without
/// real network state.
protocol ConnectivityMonitoring: Sendable {
    var isConnected: Bool { get async }
    func statusStream() -> AsyncStream<Bool>
}

/// Abstraction over Keychain access.
protocol SecureStoring: Sendable {
    func set(_ value: String, forKey key: String) throws
    func get(_ key: String) throws -> String?
    func delete(_ key: String) throws
}

/// Abstraction over the image cache used by the grid/detail views.
protocol ImageCaching: Sendable {
    func thumbnail(for url: URL, targetSize: CGSize) async throws -> Data
    func clearCache() async
    var currentDiskUsageBytes: Int { get async }
}

/// Publishes sync progress to the UI.
protocol SyncEngineProtocol: Sendable {
    func syncNow() async
    func statusStream() -> AsyncStream<SyncStatus>
    var currentStatus: SyncStatus { get async }
}
