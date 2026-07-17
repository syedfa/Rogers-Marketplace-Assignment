import Foundation

/// URLSession-backed implementation of `APIClientProtocol`, talking to the
/// JSON Server mock backend. The base URL is resolved lazily on every call
/// (via a closure) so the user can change the server address from Settings
/// without needing to reconstruct this client.
actor APIClient: APIClientProtocol {
    private let baseURLProvider: @Sendable () -> URL
    private let session: URLSession
    private let tokenProvider: SecureStoring?
    private static let tokenKey = "apiToken"

    init(
        baseURLProvider: @escaping @Sendable () -> URL,
        session: URLSession = .shared,
        tokenProvider: SecureStoring? = nil
    ) {
        self.baseURLProvider = baseURLProvider
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func fetchListings() async throws -> [Listing] {
        let request = try makeRequest(path: "/listings", method: "GET")
        let data = try await perform(request)
        let records = try decode([ListingRecord].self, from: data)
        return records.map(resolvingImageURLs)
    }

    func createListing(_ listing: Listing) async throws -> Listing {
        let record = ListingRecord(listing: listing)
        let body = try JSONEncoder.marketplace.encode(record)
        let request = try makeRequest(path: "/listings", method: "POST", body: body)
        let data = try await perform(request)
        return resolvingImageURLs(try decode(ListingRecord.self, from: data))
    }

    func updateListing(_ listing: Listing) async throws -> Listing {
        let record = ListingRecord(listing: listing)
        let body = try JSONEncoder.marketplace.encode(record)
        let request = try makeRequest(path: "/listings/\(listing.id)", method: "PUT", body: body)
        let data = try await perform(request)
        return resolvingImageURLs(try decode(ListingRecord.self, from: data))
    }

    /// JSON Server's static file middleware serves seed images as
    /// server-relative paths (e.g. `/images/placeholder-0.jpg`). Resolve
    /// those against the current base URL so `ImageCache`/`URLSession`
    /// always see a fully-qualified URL; `data:` URLs (locally created
    /// listings) and already-absolute URLs pass through unchanged.
    private func resolvingImageURLs(_ record: ListingRecord) -> Listing {
        var listing = record.asListing()
        let base = baseURLProvider()
        listing.imageURLs = listing.imageURLs.map { urlString in
            if urlString.hasPrefix("data:") || urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
                return urlString
            }
            return URL(string: urlString, relativeTo: base)?.absoluteString ?? urlString
        }
        return listing
    }

    private func makeRequest(path: String, method: String, body: Data? = nil) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURLProvider()) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = try? tokenProvider?.get(Self.tokenKey) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Non-HTTP response")
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 400...499:
            throw APIError.clientError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        case 500...599:
            throw APIError.serverError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        default:
            throw APIError.transport("Unexpected status \(http.statusCode)")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder.marketplace.decode(type, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
