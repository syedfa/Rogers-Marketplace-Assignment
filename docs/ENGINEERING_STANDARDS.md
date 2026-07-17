# Engineering Standards

## Layering

```
Presentation → Domain ← Data
```

- **`Domain`** is pure Swift: models, protocols, validation, conflict
  resolution. No `import SwiftData`, no `import SwiftUI`, no
  `import Foundation`-adjacent networking types beyond `Foundation` itself.
  This is enforced by convention (reviewed in PRs), not a build rule — if a
  `Domain` file ever needs `SwiftData`, that's a sign the type belongs in
  `Data` instead.
- **`Data`** implements every `Domain` protocol exactly once
  (`ListingRepository` ↔ `ListingRepositoryProtocol`, `APIClient` ↔
  `APIClientProtocol`, etc). ViewModels depend on the protocol type, never
  the concrete implementation — that's what let every sync/persistence test
  in this repo run against an in-memory `ModelContainer` or a stubbed
  `URLSession` instead of a real backend.
- **`Presentation`** never imports `SwiftData` or constructs a `URLRequest`.
  If a view needs data, it asks a `@MainActor @Observable` ViewModel, which
  asks a `Domain` protocol.
- **`App/AppDependencies.swift`** is the single composition root. It's the
  only file in the app that knows every concrete `Data` type exists.

## Concurrency

- Swift's default actor isolation for this target is `MainActor`
  (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), matching modern
  Swift 6-style projects — types are main-actor by default unless they
  explicitly opt out.
- Anything that does real work off the main thread is an explicit `actor`:
  `ListingRepository` (`@ModelActor`), `APIClient`, `SyncEngine`,
  `ImageCache`. Each owns its serialized state instead of relying on locks,
  except where a lock is unavoidable because a type wraps a
  non-actor-isolated system API (`ConnectivityMonitor` wrapping
  `NWPathMonitor`'s own callback queue; `StubURLProtocol` in tests, whose
  `startLoading()` is invoked by `URLSession` off any actor).
- ViewModels are `@MainActor @Observable` — UI state mutation always happens
  on the main actor, and `@Observable` (not `ObservableObject`) is used
  throughout for lower-overhead, property-level change tracking.
- Async sequences (`AsyncStream`) are used for both sync status
  (`SyncEngineProtocol.statusStream()`) and connectivity
  (`ConnectivityMonitoring.statusStream()`) rather than a callback or
  Combine — a `for await` loop is the plainest way to express "keep this UI
  state in sync with that actor's state" without extra machinery.

## Error handling

- `Domain` errors are typed enums (`APIError`, `ValidationError`,
  `RepositoryError`) — never `Error` boxed as a string, so callers can
  `switch` and tests can assert on the exact case.
- Sync failures are caught **per pending change** in `SyncEngine.drainOutbox`
  and recorded (`recordFailure`, incrementing `attemptCount`) rather than
  aborting the whole sync — one bad record shouldn't block every other
  listing from syncing.
- Presentation-layer failures (a failed `repository.create(_:)` call, say)
  are swallowed with `try?` at the ViewModel boundary only where the UI
  already reflects the authoritative state afterward (e.g. a favorite
  toggle just doesn't visually update if it silently failed — there's
  nothing further to report for a local-only, idempotent operation). Where
  the user needs to *see* the failure — sync status, form validation — it's
  surfaced explicitly (`SyncStatusBanner`, inline field errors).
- No force-unwraps outside of two well-understood categories: statically
  known-valid literals (e.g. `URL(string: "http://localhost:3000")!`) and
  `JSONEncoder`/`JSONDecoder` calls against a type whose `Codable`
  conformance has no way to fail for the shape of data involved.

## Naming

- `Domain` models are plain nouns (`Listing`, `Category`, `PendingChange`).
- `Data` implementations are named after what they *are*, not a `Impl`/`Live`
  suffix: `ListingRepository`, `APIClient`, `ImageCache`. Their protocols
  carry the suffix instead (`ListingRepositoryProtocol`,
  `APIClientProtocol`) since there's exactly one production implementation
  of each and tests reach for a hand-written fake, not a generated one.
- Test doubles are `Fake*` (stateful, general-purpose:
  `FakeAPIClient`, `FakeConnectivityMonitor`) or `InMemory*` (a real,
  minimal implementation backed by a dictionary: `InMemorySecureStore`) —
  never `Mock*`, to avoid implying record/verify mocking machinery this
  codebase doesn't use.

## Testing

- **Swift Testing** (`@Test`/`#expect`), not XCTest — see
  [README.md#testing](../README.md#testing) for the full suite list.
- Tests exercise real production types wherever feasible
  (`ListingRepository` against an in-memory `ModelContainer`, `APIClient`
  against a stubbed `URLProtocol`) rather than re-implementing their logic
  in a fake — a fake `ListingRepository` would just be a second copy of the
  coalescing/outbox logic that could silently drift from the real one.
- `StubURLProtocol` (test-only) routes each `URLSession` to its own handler
  via a UUID carried in a request header, rather than one shared static
  closure — Swift Testing runs suites concurrently by default, and a single
  shared mutable handler let one test's stubbed response leak into another
  running at the same time (this was a real, reproduced bug during
  development — see commit history).
- No UI snapshot tests. `Presentation` is kept thin enough (every view
  either has no branching logic or delegates it to a tested ViewModel) that
  the cost of introducing a snapshot-testing setup wasn't justified for this
  scope; the existing XCUITest launch test remains as a smoke test.

## Commit conventions

- Imperative, present-tense subject line (`Add conflict resolver`, not
  `Added` or `Adds`).
- A commit is buildable and, where applicable, green on `xcodebuild test` —
  this repo was built test-first (diagrams → tests → implementation), and
  that discipline is meant to hold going forward too.

## Lint & CI

- `.swiftlint.yml` at the repo root (run `swiftlint` locally if installed;
  it's a development-time tool, not a runtime dependency, so it doesn't
  conflict with the "no third-party libraries" constraint on the app
  itself).
- `.github/workflows/ci.yml` runs `xcodebuild test` on every push/PR against
  an iOS Simulator destination.
