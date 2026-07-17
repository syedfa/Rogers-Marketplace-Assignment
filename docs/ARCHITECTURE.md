# Architecture

Offline-first marketplace app. SwiftUI + SwiftData, no third-party
dependencies. MVVM presentation layer over a Repository/Domain core, with an
outbox-based sync engine reconciling local edits against a mock REST API
(JSON Server).

## Layering rules

- **Presentation** never imports SwiftData or Foundation networking types
  directly — it talks to `Domain` protocols only.
- **Domain** is pure Swift (models, protocols, validation, conflict
  resolution). No SwiftData, no URLSession, no UIKit/SwiftUI imports. This is
  what makes `ConflictResolverTests` and `ListingValidatorTests` fast,
  deterministic, and free of any framework setup.
- **Data** implements the Domain protocols: SwiftData persistence, URLSession
  networking, disk/memory image caching, Keychain, connectivity, and the sync
  engine itself.
- Dependencies point inward: `Presentation → Domain ← Data`. `AppDependencies`
  (composition root) is the only place that wires concrete `Data` types into
  `Domain` protocols and hands them to ViewModels.

## Architecture Diagram

```mermaid
flowchart TB
    subgraph Presentation["Presentation (SwiftUI, @Observable ViewModels, @MainActor)"]
        HomeV[HomeView<br/>2-col grid + search + categories] --- HomeVM[HomeViewModel]
        DetailV[ListingDetailView] --- DetailVM[ListingDetailViewModel]
        SellV[CreateListingView<br/>photo picker + form] --- SellVM[CreateListingViewModel]
        SavedV[SavedView] --- SavedVM[SavedViewModel]
        SettingsV[SettingsView<br/>merge strategy, server URL] --- SettingsVM[SettingsViewModel]
        SyncBadge[SyncStatusBanner]
    end

    subgraph Domain["Domain (pure Swift, no imports beyond Foundation)"]
        Repo{{ListingRepositoryProtocol}}
        SyncP{{SyncEngineProtocol}}
        Resolver{{ConflictResolver<br/>LWW / FieldMerge}}
        Validator[ListingValidator]
        DTO[Listing DTO / SyncStatus]
    end

    subgraph Data["Data"]
        RepoImpl[ListingRepository]
        subgraph Sync["Sync"]
            Engine[SyncEngine<br/>outbox drain + pull]
            Outbox[(PendingChange<br/>@Model outbox)]
        end
        subgraph Persistence["Persistence (SwiftData)"]
            Store[(ModelContainer<br/>ListingEntity)]
        end
        subgraph Network["Network (URLSession)"]
            API[APIClient + ListingsEndpoint]
            BGUpload[BackgroundUploader<br/>background URLSession]
        end
        subgraph Images["Images"]
            ImgCache[ImageCache: NSCache, 50 MB cost cap]
            ImgDisk[ImageStore: Caches/images]
            Thumb[ThumbnailGenerator: ImageIO downsample]
        end
        Path[ConnectivityMonitor<br/>NWPathMonitor]
        Keychain[KeychainStore]
    end

    subgraph External["External"]
        JSON[JSON Server :3000<br/>db.json + static images]
        BGTask[BGTaskScheduler]
        Photos[PhotosPicker / Camera<br/>+ permission primer]
    end

    HomeVM & DetailVM & SellVM & SavedVM --> Repo
    SettingsVM --> SyncP
    SyncBadge --> SyncP
    Repo -.implemented by.-> RepoImpl
    SyncP -.implemented by.-> Engine
    RepoImpl --> Store & Outbox
    Engine --> Outbox & Store & API & Resolver
    Engine --> Path
    API --> JSON
    API --> Keychain
    BGUpload --> JSON
    BGTask --> Engine
    SellVM --> Photos & Validator
    HomeVM --> ImgCache
    ImgCache --> ImgDisk --> Thumb
```

## Sequence Diagrams

### 1. Offline create → reconnect → sync

```mermaid
sequenceDiagram
    actor User
    participant VM as CreateListingViewModel
    participant Val as ListingValidator
    participant Repo as ListingRepository
    participant DB as SwiftData
    participant Net as ConnectivityMonitor
    participant Sync as SyncEngine
    participant API as APIClient
    participant JS as JSON Server

    User->>VM: Fill form + attach photo, tap Publish
    VM->>Val: validate(title, price, description)
    Val-->>VM: ok (or field errors shown inline)
    VM->>Repo: create(listing, imageData)
    Repo->>DB: insert ListingEntity (syncStatus = .pendingCreate)
    Repo->>DB: insert PendingChange(.create, snapshot)
    Repo-->>VM: saved locally — UI shows "Pending upload" badge
    Note over Net: Device offline → nothing else happens

    Net-->>Sync: path became .satisfied
    Sync->>DB: fetch PendingChanges (FIFO)
    loop each pending change
        Sync->>API: POST /listings (JSON + image upload)
        API->>JS: HTTP request
        JS-->>API: 201 Created (server record)
        Sync->>DB: mark ListingEntity .synced, delete PendingChange
    end
    Sync->>API: GET /listings (pull phase)
    Sync->>DB: reconcile via ConflictResolver
    Sync-->>VM: status .synced → badge disappears
```

### 2. Browse with cache-first images (200 listings)

```mermaid
sequenceDiagram
    participant Grid as HomeView (LazyVGrid)
    participant VM as HomeViewModel
    participant Repo as ListingRepository
    participant DB as SwiftData
    participant IC as ImageCache (NSCache)
    participant Disk as ImageStore (disk)
    participant TG as ThumbnailGenerator
    participant JS as JSON Server

    Grid->>VM: onAppear
    VM->>Repo: observeListings(query)
    Repo->>DB: FetchDescriptor (sorted, indexed)
    DB-->>Grid: 200 rows render instantly (offline OK)
    par per visible cell
        Grid->>IC: thumbnail(for: url, size: cellSize)
        alt memory hit
            IC-->>Grid: UIImage (no decode)
        else disk hit
            IC->>Disk: read file
            Disk->>TG: downsample to cellSize·scale (ImageIO, no full decode)
            TG-->>IC: thumbnail → cache w/ byte cost
        else miss
            IC->>JS: GET /images/xyz.jpg
            JS-->>Disk: write original to disk
            Disk->>TG: downsample
            TG-->>IC: thumbnail → cache
        end
    end
    Note over IC: memory warning → NSCache evicts;<br/>disk survives for next launch
```

### 3. Conflict resolution during pull (both strategies)

```mermaid
sequenceDiagram
    participant Sync as SyncEngine
    participant API as APIClient
    participant CR as ConflictResolver
    participant DB as SwiftData

    Sync->>API: GET /listings
    API-->>Sync: remote records
    loop each remote record
        Sync->>DB: local version + pending state
        alt no local edits
            Sync->>DB: upsert remote (server wins trivially)
        else local has pending update (conflict)
            Sync->>CR: resolve(local, remote, strategy)
            alt Last-Write-Wins
                CR-->>Sync: whichever updatedAt is newer, wholesale
            else Field-Merge
                CR-->>Sync: locally-edited fields kept,<br/>untouched fields from remote
            end
            Sync->>DB: write resolved record, keep/drop PendingChange accordingly
        end
    end
    Sync-->>Sync: publish SyncStatus(.synced, resolvedConflicts: n)
```

### 4. Background image upload when connectivity returns (app backgrounded)

```mermaid
sequenceDiagram
    participant OS as iOS (BGTaskScheduler)
    participant Coord as BackgroundTaskCoordinator
    participant Net as ConnectivityMonitor
    participant Sync as SyncEngine
    participant Up as BackgroundUploader<br/>(background URLSession)
    participant JS as JSON Server

    Note over Coord: App enters background with<br/>pending changes → schedule BGProcessingTask<br/>(requiresNetworkConnectivity = true)
    OS-->>Coord: launch task when network available
    Coord->>Net: confirm path .satisfied
    Coord->>Sync: drainOutbox()
    Sync->>Up: upload image files (uploadTask from file URL)
    Up->>JS: POST multipart/body per image
    JS-->>Up: 201 Created
    Note over Up: background URLSession survives<br/>suspension; delegate fires on completion
    Up-->>Sync: uploads complete
    Sync->>JS: POST/PATCH listing JSON
    Sync-->>Coord: outbox empty → setTaskCompleted(success: true)
    Note over Coord: reschedule if work remains<br/>or task expired (expirationHandler)
```

## Key Decisions & Trade-offs

| Decision | Choice | Trade-off / Why |
|---|---|---|
| Architecture | MVVM + Repository, protocol-first DI (no framework) | Testable seams without library DI; ViewModels are `@Observable @MainActor` |
| Source of truth | SwiftData is *always* the source of truth; UI never reads the network directly | True offline-first; network only feeds the local store |
| Offline writes | Outbox pattern (`PendingChange` @Model rows), drained FIFO on reconnect | Simple, durable, inspectable; avoids fragile in-memory queues |
| Conflict resolution | Strategy protocol: **Last-Write-Wins** (timestamp) and **Field-Merge**; user picks in Settings | Assignment asks for exactly this; strategy object is pure → easily unit tested |
| Images | Disk store (Caches dir) + `NSCache` (cost-limited) + ImageIO downsampling for thumbnails | Bounded memory; no full-size decodes in the grid |
| Background work | `NWPathMonitor` triggers foreground sync; `BGProcessingTask` + background `URLSession` for uploads when app is backgrounded | Real BG tasks are flaky on simulator — documented in README with debugger trigger instructions |
| Token storage | Keychain wrapper storing a mock API token (JSON Server needs none — demonstrates the pattern) | Shows secure-storage competence without inventing fake auth flows |
| Lint/CI | `.swiftlint.yml` config + GitHub Actions workflow (build + test); SwiftLint runs only if installed (it's a dev tool, not an app library) | Keeps "no libraries" constraint intact for the app itself |
| Favorites | Local-only (not synced) | Mock API has no user identity; documented as a deliberate scope cut |

## Data Model

```swift
@Model final class ListingEntity {
    @Attribute(.unique) var id: String        // UUID string, client-generated (works offline)
    var title: String
    var listingDescription: String
    var price: Decimal
    var category: String
    var imageURLs: [String]                   // remote URLs or local file names (pending upload)
    var isFavorite: Bool                      // local-only
    var createdAt: Date
    var updatedAt: Date                       // drives LWW
    var syncStatusRaw: String                 // synced | pendingCreate | pendingUpdate | failed
    var locallyEditedFields: [String]         // drives field-merge
}

@Model final class PendingChangeEntity {      // the outbox
    @Attribute(.unique) var id: String
    var listingID: String
    var kindRaw: String                       // create | update
    var payload: Data                         // JSON snapshot of ListingDTO at edit time
    var localImageFileNames: [String]         // images awaiting upload
    var queuedAt: Date
    var attemptCount: Int
    var lastError: String?
}
```

Domain layer works with a plain `Listing` struct (Sendable, Codable) — entities
never leak into ViewModels. JSON Server's `db.json` mirrors `Listing`'s coding
keys.

## Project Structure

```
Rogers-Marketplace Assignment/
├── App/                    MarketplaceApp.swift, AppDependencies.swift (composition root)
├── Domain/
│   ├── Models/             Listing.swift, SyncStatus.swift, PendingChange.swift, Category.swift
│   ├── Protocols/          ListingRepositoryProtocol, SyncEngineProtocol, APIClientProtocol,
│   │                       ImageCacheProtocol, ConnectivityMonitorProtocol, SecureStoreProtocol
│   ├── Sync/               ConflictResolver.swift (LWW + FieldMerge), MergeStrategy.swift
│   └── Validation/         ListingValidator.swift
├── Data/
│   ├── Persistence/        ModelContainerFactory, ListingEntity, PendingChangeEntity, mappers
│   ├── Repository/         ListingRepository.swift
│   ├── Network/            APIClient, Endpoint, ListingsEndpoint, APIError
│   ├── Sync/               SyncEngine.swift, BackgroundTaskCoordinator.swift, BackgroundUploader.swift
│   ├── Images/             ImageCache, ImageStore, ThumbnailGenerator
│   ├── Connectivity/       ConnectivityMonitor.swift (NWPathMonitor)
│   └── Security/           KeychainStore.swift
├── Presentation/
│   ├── Home/  Detail/  Sell/  Saved/  Settings/
│   └── Components/         ListingCard, SyncStatusBanner, CachedThumbnailView,
│                           CameraPermissionPrimer, PriceText, CategoryChips
Rogers-Marketplace AssignmentTests/   (Swift Testing)
mock-server/                db.json (generated), seed.mjs, public/images/
scripts/                    setup.sh
docs/                       ARCHITECTURE.md, ENGINEERING_STANDARDS.md
.github/workflows/ci.yml    build + test on macos runner
.swiftlint.yml
```

## Security, Performance, Standards

- **Security**: Keychain-stored mock token attached as `Authorization` header;
  all user input validated in the Domain layer before persistence; server URL
  validated (scheme + host present) before use; no force-unwraps policy; ATS
  scoped to local networking only (no arbitrary-loads exception).
- **Performance**: SwiftData-backed grid handles 200+ rows via `LazyVGrid`;
  images downsampled with `CGImageSourceCreateThumbnailAtIndex` (never a
  full-size decode into memory); `NSCache.totalCostLimit` ≈ 50 MB with
  byte-accurate costs; decode work happens off the main actor; sync batches
  network calls; `NWPathMonitor` runs on a background queue.
- **Standards**: see [ENGINEERING_STANDARDS.md](ENGINEERING_STANDARDS.md) for
  naming, layering, concurrency, and error-handling conventions.
