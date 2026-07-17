import SwiftUI

/// `AppDependencies` is intentionally not `@Observable` — it's a static
/// composition root, not reactive state — so it rides through the
/// environment via a plain custom key rather than the `Observable`-only
/// `View.environment(_:)` overload.
private struct AppDependenciesKey: EnvironmentKey {
    @MainActor static let defaultValue = AppDependencies.shared
}

extension EnvironmentValues {
    var dependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}
