import Foundation
import Observation

/// Backs both `HomeView` (the full feed) and `SavedView` (favorites only) —
/// the two screens differ only in one query parameter, so they share this
/// view model instead of duplicating fetch/search/favorite logic.
@MainActor
@Observable
final class ListingGridViewModel {
    private(set) var listings: [Listing] = []
    private(set) var isLoading = false
    var searchText: String = "" {
        didSet { scheduleReload() }
    }
    var selectedCategory: Category? {
        didSet { scheduleReload() }
    }

    private let repository: ListingRepositoryProtocol
    private let syncEngine: SyncEngineProtocol
    private let favoritesOnly: Bool
    private var reloadTask: Task<Void, Never>?
    private var syncObservationTask: Task<Void, Never>?

    init(repository: ListingRepositoryProtocol, syncEngine: SyncEngineProtocol, favoritesOnly: Bool) {
        self.repository = repository
        self.syncEngine = syncEngine
        self.favoritesOnly = favoritesOnly
    }

    func onAppear() {
        scheduleReload(debounced: false)
        observeSyncCompletionsIfNeeded()
    }

    /// Manual pull-to-refresh: kick a sync and reload once it settles,
    /// rather than just re-reading whatever's already on disk.
    func refresh() async {
        await syncEngine.syncNow()
        await reload()
    }

    func toggleFavorite(_ listing: Listing) {
        let newValue = !listing.isFavorite
        Task {
            do {
                try await repository.setFavorite(id: listing.id, isFavorite: newValue)
                applyFavoriteChange(listingID: listing.id, isFavorite: newValue)
            } catch {
                // Local-only write failed silently; nothing further to report.
            }
        }
    }

    /// Reflects an already-persisted favorite change in the in-memory list
    /// immediately, without a full reload. Used both by `toggleFavorite`
    /// above and by the detail screen, which persists the change itself
    /// (it can be reached from either the full feed or the favorites-only
    /// feed) and calls back in here so whichever grid the user returns to
    /// is correct right away — not just after the next sync-driven reload.
    func applyFavoriteChange(listingID: String, isFavorite: Bool) {
        guard let index = listings.firstIndex(where: { $0.id == listingID }) else { return }
        if favoritesOnly && !isFavorite {
            listings.remove(at: index)
        } else {
            listings[index].isFavorite = isFavorite
        }
    }

    /// The initial pull can (and typically does) land new listings after
    /// this screen's first fetch has already returned — without this, the
    /// grid would stay stuck showing whatever was on disk at launch until
    /// the user manually pulls to refresh or edits the search text.
    private func observeSyncCompletionsIfNeeded() {
        guard syncObservationTask == nil else { return }
        syncObservationTask = Task { [weak self] in
            guard let self else { return }
            for await status in await syncEngine.statusStream() {
                guard case .synced = status.phase else { continue }
                await self.reload()
            }
        }
    }

    private func scheduleReload(debounced: Bool = true) {
        reloadTask?.cancel()
        reloadTask = Task {
            if debounced {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
            }
            await reload()
        }
    }

    private func reload() async {
        isLoading = true
        let query = ListingQuery(searchText: searchText, category: selectedCategory, favoritesOnly: favoritesOnly)
        listings = (try? await repository.fetchListings(matching: query)) ?? []
        isLoading = false
    }
}
