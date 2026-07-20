import Foundation

/// Polls `condition` until it returns true or `timeout` elapses — for
/// asserting on state that changes asynchronously from a detached Task
/// (e.g. `SyncEngine`'s connectivity observation, or a ViewModel's
/// background reload), where there's no single call to `await` on.
func waitUntil(timeout: Duration = .seconds(2), _ condition: () async -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}
