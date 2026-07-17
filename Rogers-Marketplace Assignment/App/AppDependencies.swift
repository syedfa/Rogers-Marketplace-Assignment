import Foundation
import SwiftData

/// Composition root. Built once at launch and threaded down via
/// `.environment`; every concrete `Data` type is constructed here and
/// exposed to the rest of the app only through `Domain` protocols.
@MainActor
final class AppDependencies {
    /// A single shared instance so `AppDelegate` (which registers the
    /// background task before the SwiftUI `App` scene is built) and the
    /// SwiftUI view hierarchy observe the exact same `SyncEngine`.
    static let shared = AppDependencies()

    static let serverURLDefaultsKey = "marketplace.serverURL"
    static let mergeStrategyDefaultsKey = "marketplace.mergeStrategy"
    static let apiTokenKeychainKey = "apiToken"
    static let defaultServerURLString = "http://localhost:3000"

    let modelContainer: ModelContainer
    let repository: ListingRepository
    let apiClient: APIClient
    let connectivityMonitor: ConnectivityMonitor
    let imageCache: ImageCache
    let keychain: KeychainStore
    let syncEngine: SyncEngine
    let backgroundTaskCoordinator: BackgroundTaskCoordinator
    let backgroundUploader: BackgroundUploader

    private init() {
        do {
            modelContainer = try ModelContainerFactory.makeContainer()
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
        repository = ListingRepository(modelContainer: modelContainer)
        keychain = KeychainStore()

        // A mock but real token, so the Keychain/Authorization-header path
        // is genuinely exercised even though JSON Server itself ignores it.
        if (try? keychain.get(Self.apiTokenKeychainKey)) == nil {
            try? keychain.set(UUID().uuidString, forKey: Self.apiTokenKeychainKey)
        }

        let baseURLProvider: @Sendable () -> URL = {
            let stored = UserDefaults.standard.string(forKey: AppDependencies.serverURLDefaultsKey)
            return URL(string: stored ?? "") ?? URL(string: AppDependencies.defaultServerURLString)!
        }
        apiClient = APIClient(baseURLProvider: baseURLProvider, tokenProvider: keychain)
        connectivityMonitor = ConnectivityMonitor()
        imageCache = ImageCache(store: ImageStore(directory: ImageStore.defaultDirectory()))

        let strategyProvider: @Sendable () -> MergeStrategy = {
            let raw = UserDefaults.standard.string(forKey: AppDependencies.mergeStrategyDefaultsKey)
            return raw.flatMap(MergeStrategy.init(rawValue:)) ?? .lastWriteWins
        }
        syncEngine = SyncEngine(
            repository: repository,
            apiClient: apiClient,
            connectivity: connectivityMonitor,
            strategyProvider: strategyProvider
        )
        backgroundTaskCoordinator = BackgroundTaskCoordinator(syncEngine: syncEngine)
        backgroundUploader = BackgroundUploader(baseURLProvider: baseURLProvider, tokenProvider: keychain)

        // Syncs immediately, then retries automatically on every
        // offline→online transition — see `SyncEngine.startObservingConnectivity()`.
        let syncEngine = syncEngine
        Task { await syncEngine.startObservingConnectivity() }
    }
}
