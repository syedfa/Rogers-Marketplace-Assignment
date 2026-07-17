import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    var serverURLText: String
    var mergeStrategy: MergeStrategy {
        didSet { UserDefaults.standard.set(mergeStrategy.rawValue, forKey: AppDependencies.mergeStrategyDefaultsKey) }
    }
    private(set) var pendingCount = 0
    private(set) var diskUsageBytes = 0
    private(set) var urlError: String?

    let syncStatus: SyncStatusViewModel

    private let repository: ListingRepositoryProtocol
    private let imageCache: ImageCaching

    init(repository: ListingRepositoryProtocol, imageCache: ImageCaching, syncEngine: SyncEngineProtocol) {
        self.repository = repository
        self.imageCache = imageCache
        self.syncStatus = SyncStatusViewModel(syncEngine: syncEngine)

        let storedURL = UserDefaults.standard.string(forKey: AppDependencies.serverURLDefaultsKey)
        serverURLText = storedURL ?? AppDependencies.defaultServerURLString
        let storedStrategy = UserDefaults.standard.string(forKey: AppDependencies.mergeStrategyDefaultsKey)
        mergeStrategy = storedStrategy.flatMap(MergeStrategy.init(rawValue:)) ?? .lastWriteWins
    }

    func refresh() async {
        pendingCount = (try? await repository.pendingChanges().count) ?? 0
        diskUsageBytes = await imageCache.currentDiskUsageBytes
    }

    func validateAndSaveURL() {
        guard let url = URL(string: serverURLText),
              let scheme = url.scheme, ["http", "https"].contains(scheme),
              url.host != nil else {
            urlError = "Enter a valid http(s) URL, e.g. http://192.168.1.10:3000"
            return
        }
        urlError = nil
        UserDefaults.standard.set(serverURLText, forKey: AppDependencies.serverURLDefaultsKey)
    }

    func clearImageCache() {
        Task {
            await imageCache.clearCache()
            await refresh()
        }
    }

    func syncNow() {
        syncStatus.syncNow()
    }
}
