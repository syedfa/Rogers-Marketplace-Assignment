import Foundation

/// Drives the outbox-drain-then-pull sync cycle described in
/// `docs/ARCHITECTURE.md`. An actor so `syncNow()` calls that overlap (e.g.
/// a manual "Sync now" tap while a connectivity-triggered sync is already
/// running) serialize instead of racing on `status`.
actor SyncEngine: SyncEngineProtocol {
    private let repository: ListingRepositoryProtocol
    private let apiClient: APIClientProtocol
    private let connectivity: ConnectivityMonitoring
    private let resolver: ConflictResolver
    private let strategyProvider: @Sendable () -> MergeStrategy

    private(set) var currentStatus: SyncStatus = .initial
    private var continuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]
    private var connectivityObservationTask: Task<Void, Never>?

    init(
        repository: ListingRepositoryProtocol,
        apiClient: APIClientProtocol,
        connectivity: ConnectivityMonitoring,
        resolver: ConflictResolver = ConflictResolver(),
        strategyProvider: @escaping @Sendable () -> MergeStrategy
    ) {
        self.repository = repository
        self.apiClient = apiClient
        self.connectivity = connectivity
        self.resolver = resolver
        self.strategyProvider = strategyProvider
    }

    deinit {
        connectivityObservationTask?.cancel()
    }

    /// Attempts a sync immediately (covers app launch), then keeps
    /// listening for connectivity changes and retries automatically every
    /// time the device transitions from offline to online. This is what
    /// guarantees a queued offline create/edit — or one that failed
    /// because the server was unreachable — actually gets retried once the
    /// network comes back, without the user needing to relaunch the app,
    /// pull-to-refresh, or tap "Sync Now". Safe to call more than once;
    /// only the first call starts anything.
    ///
    /// Note this reacts to *device* connectivity (`NWPathMonitor`), not
    /// specifically "the configured server is reachable" — a satisfied
    /// network path with the mock server simply not running won't trigger
    /// a retry on its own. `syncNow()` still fails safely in that case
    /// (`SyncStatus.failed`), and the user has "Sync Now" / pull-to-refresh
    /// as an explicit fallback.
    func startObservingConnectivity() {
        guard connectivityObservationTask == nil else { return }
        connectivityObservationTask = Task { [weak self, connectivity] in
            guard let self else { return }
            await self.syncNow()
            var wasConnected = await connectivity.isConnected
            for await isConnected in connectivity.statusStream() {
                if isConnected && !wasConnected {
                    await self.syncNow()
                }
                wasConnected = isConnected
            }
        }
    }

    func statusStream() -> AsyncStream<SyncStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.yield(currentStatus)
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    func syncNow() async {
        guard await connectivity.isConnected else {
            let pending = (try? await repository.pendingChanges().count) ?? 0
            publish(SyncStatus(phase: .offline, pendingCount: pending, resolvedConflicts: currentStatus.resolvedConflicts))
            return
        }

        publish(SyncStatus(phase: .syncing, pendingCount: currentStatus.pendingCount, resolvedConflicts: 0))

        do {
            try await drainOutbox()
            let resolvedConflicts = try await pullAndReconcile()
            let pendingCount = try await repository.pendingChanges().count
            publish(SyncStatus(phase: .synced(at: Date()), pendingCount: pendingCount, resolvedConflicts: resolvedConflicts))
        } catch {
            let pendingCount = (try? await repository.pendingChanges().count) ?? currentStatus.pendingCount
            publish(SyncStatus(phase: .failed(String(describing: error)), pendingCount: pendingCount, resolvedConflicts: 0))
        }
    }

    private func drainOutbox() async throws {
        let pending = try await repository.pendingChanges().sorted { $0.queuedAt < $1.queuedAt }
        for change in pending {
            do {
                let serverListing: Listing
                switch change.kind {
                case .create:
                    serverListing = try await apiClient.createListing(change.snapshot)
                case .update:
                    serverListing = try await apiClient.updateListing(change.snapshot)
                }
                var synced = serverListing
                synced.isFavorite = change.snapshot.isFavorite
                // markSynced also clears this change's outbox row.
                try await repository.markSynced(listingID: change.listingID, resolved: synced)
            } catch {
                try await repository.recordFailure(pendingChangeID: change.id, error: String(describing: error))
            }
        }
    }

    private func pullAndReconcile() async throws -> Int {
        let remoteListings = try await apiClient.fetchListings()
        let pendingByListingID = Dictionary(
            uniqueKeysWithValues: try await repository.pendingChanges().map { ($0.listingID, $0) }
        )
        var resolvedConflictCount = 0
        var toUpsert: [Listing] = []

        for remote in remoteListings {
            guard pendingByListingID[remote.id] != nil,
                  let local = try await repository.fetchListing(id: remote.id) else {
                toUpsert.append(remote)
                continue
            }

            resolvedConflictCount += 1
            let strategy = strategyProvider()
            let (resolved, needsRepush) = resolver.resolve(local: local, remote: remote, strategy: strategy)
            if needsRepush {
                try await repository.update(resolved, editedFields: resolved.locallyEditedFields)
            } else {
                try await repository.markSynced(listingID: remote.id, resolved: resolved)
            }
        }

        if !toUpsert.isEmpty {
            try await repository.upsertFromRemote(toUpsert)
        }
        return resolvedConflictCount
    }

    private func publish(_ status: SyncStatus) {
        currentStatus = status
        for continuation in continuations.values {
            continuation.yield(status)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
