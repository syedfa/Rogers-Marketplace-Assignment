import Foundation

/// Uploads a single queued outbox change via a background `URLSession`, so
/// it keeps draining even if the app is suspended while the request is in
/// flight — the OS relaunches the app in the background to deliver the
/// completion event. See sequence diagram 4 in `docs/ARCHITECTURE.md`.
///
/// JSON Server (the mock backend) has no multipart upload endpoint, so each
/// "upload" is really a plain POST/PUT of the listing JSON — images are
/// already embedded as base64 `data:` URLs by the time a listing reaches
/// the outbox. Background upload tasks require `uploadTask(fromFile:)`
/// rather than an in-memory buffer, so the payload is written to a temp
/// file first.
///
/// This class is deliberately fire-and-forget: it does not itself update
/// SwiftData from the background delegate callback (the app may be
/// suspended before that callback runs, and re-standing the persistence
/// stack from a background launch is out of scope here). Convergence is
/// instead guaranteed by `SyncEngine`'s pull phase: because listing IDs are
/// client-generated and round-trip through JSON Server unchanged, the next
/// foreground `syncNow()` sees its own outbox entry, matches it against the
/// now-updated remote record, and — since a plain create/update carries no
/// locally-edited-fields conflict — resolves to the remote version and
/// clears the outbox row. A successful background upload is never lost,
/// merely reconciled a little later.
final class BackgroundUploader: NSObject, URLSessionDelegate, @unchecked Sendable {
    static let sessionIdentifier = "ca.cybermedia.RogersMarketplace.bg-upload"

    private var session: URLSession!
    private let baseURLProvider: @Sendable () -> URL
    private let tokenProvider: SecureStoring?

    /// Called on the main queue once all background events have been
    /// delivered — forward this to the `UIApplication` completion handler
    /// captured in `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    var backgroundCompletionHandler: (() -> Void)?

    init(baseURLProvider: @escaping @Sendable () -> URL, tokenProvider: SecureStoring? = nil) {
        self.baseURLProvider = baseURLProvider
        self.tokenProvider = tokenProvider
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func enqueue(_ change: PendingChange) {
        do {
            let record = ListingRecord(listing: change.snapshot)
            let body = try JSONEncoder.marketplace.encode(record)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("upload-\(change.id).json")
            try body.write(to: tempURL, options: .atomic)

            let path = change.kind == .create ? "/listings" : "/listings/\(change.listingID)"
            guard let url = URL(string: path, relativeTo: baseURLProvider()) else { return }

            var request = URLRequest(url: url)
            request.httpMethod = change.kind == .create ? "POST" : "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = try? tokenProvider?.get("apiToken") {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            session.uploadTask(with: request, fromFile: tempURL).resume()
        } catch {
            // Best-effort: the change stays in the outbox and will be
            // retried by the next foreground sync regardless.
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }
}
