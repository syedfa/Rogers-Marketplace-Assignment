import UIKit

/// `BGTaskScheduler.register(forTaskWithIdentifier:...)` must be called
/// before the app finishes launching, and background `URLSession`
/// completion delivery requires a `UIApplicationDelegate` hook — neither
/// has a pure-SwiftUI equivalent, so a thin `UIApplicationDelegateAdaptor`
/// bridges to them.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppDependencies.shared.backgroundTaskCoordinator.registerTask()
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundUploader.sessionIdentifier else {
            completionHandler()
            return
        }
        AppDependencies.shared.backgroundUploader.backgroundCompletionHandler = completionHandler
    }
}
