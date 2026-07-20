import Testing
import Foundation
@testable import Rogers_Marketplace_Assignment

@Suite("APIClient")
struct APIClientTests {
    let baseURL = URL(string: "http://localhost:3000")!

    func makeClient(
        token: String? = "test-token",
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> APIClient {
        let keychain = InMemorySecureStore(seed: token.map { ["apiToken": $0] } ?? [:])
        return APIClient(
            baseURLProvider: { self.baseURL },
            session: StubURLProtocol.makeSession(handler: handler),
            tokenProvider: keychain
        )
    }

    func jsonResponse(status: Int, url: URL, body: Data) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, body)
    }

    static let recordJSON = """
    {
        "id": "abc-123",
        "title": "Vintage Bicycle",
        "description": "Barely used.",
        "price": 120.5,
        "category": "sports",
        "imageURLs": ["https://example.com/a.jpg"],
        "createdAt": "2024-01-01T00:00:00Z",
        "updatedAt": "2024-01-02T00:00:00Z"
    }
    """

    @Test("fetchListings issues a GET to /listings and decodes the array")
    func fetchListingsDecodesArray() async throws {
        let baseURL = baseURL
        let client = makeClient { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/listings")
            let body = Data("[\(Self.recordJSON)]".utf8)
            return self.jsonResponse(status: 200, url: baseURL, body: body)
        }

        let listings = try await client.fetchListings()

        #expect(listings.count == 1)
        #expect(listings[0].id == "abc-123")
        #expect(listings[0].title == "Vintage Bicycle")
        #expect(listings[0].price == Decimal(string: "120.5"))
        #expect(listings[0].category == .sports)
        #expect(listings[0].syncState == .synced)
        #expect(listings[0].isFavorite == false)
    }

    @Test("fetchListings resolves server-relative image paths against the base URL")
    func fetchListingsResolvesRelativeImageURLs() async throws {
        let baseURL = baseURL
        let json = """
        {
            "id": "abc-123",
            "title": "Vintage Bicycle",
            "description": "Barely used.",
            "price": 120.5,
            "category": "sports",
            "imageURLs": ["/images/placeholder-0.jpg", "https://example.com/already-absolute.jpg"],
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-02T00:00:00Z"
        }
        """
        let client = makeClient { _ in
            self.jsonResponse(status: 200, url: baseURL, body: Data("[\(json)]".utf8))
        }

        let listings = try await client.fetchListings()

        #expect(listings[0].imageURLs[0] == "http://localhost:3000/images/placeholder-0.jpg")
        #expect(listings[0].imageURLs[1] == "https://example.com/already-absolute.jpg")
    }

    @Test("fetchListings attaches the stored token as an Authorization header")
    func fetchListingsAttachesToken() async throws {
        let baseURL = baseURL
        let client = makeClient(token: "abc-token") { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc-token")
            return self.jsonResponse(status: 200, url: baseURL, body: Data("[]".utf8))
        }

        _ = try await client.fetchListings()
    }

    @Test("createListing issues a POST with a JSON body and decodes the response")
    func createListingPosts() async throws {
        let baseURL = baseURL
        let listing = TestFixtures.listing(id: "abc-123", title: "Vintage Bicycle")
        let client = makeClient { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/listings")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            // URLSession relays the body to URLProtocol as a stream, not
            // `httpBody`, once the request is actually dispatched.
            #expect(request.httpBody != nil || request.httpBodyStream != nil)
            return self.jsonResponse(status: 201, url: baseURL, body: Data(Self.recordJSON.utf8))
        }

        let result = try await client.createListing(listing)
        #expect(result.id == "abc-123")
    }

    @Test("updateListing issues a PUT to /listings/{id}")
    func updateListingPuts() async throws {
        let baseURL = baseURL
        let listing = TestFixtures.listing(id: "abc-123", title: "Updated Title")
        let client = makeClient { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.url?.path == "/listings/abc-123")
            return self.jsonResponse(status: 200, url: baseURL, body: Data(Self.recordJSON.utf8))
        }

        _ = try await client.updateListing(listing)
    }

    @Test("A 4xx response surfaces as APIError.clientError")
    func clientErrorSurfaces() async throws {
        let baseURL = baseURL
        let client = makeClient { _ in
            self.jsonResponse(status: 404, url: baseURL, body: Data("not found".utf8))
        }

        await #expect(throws: APIError.self) {
            _ = try await client.fetchListings()
        }
    }

    @Test("A 5xx response surfaces as APIError.serverError")
    func serverErrorSurfaces() async throws {
        let baseURL = baseURL
        let client = makeClient { _ in
            self.jsonResponse(status: 500, url: baseURL, body: Data("boom".utf8))
        }

        do {
            _ = try await client.fetchListings()
            Issue.record("expected serverError to be thrown")
        } catch let error as APIError {
            guard case .serverError(let status, _) = error else {
                Issue.record("expected .serverError, got \(error)")
                return
            }
            #expect(status == 500)
        }
    }

    @Test("Malformed JSON surfaces as APIError.decoding")
    func malformedJSONSurfacesAsDecodingError() async throws {
        let baseURL = baseURL
        let client = makeClient { _ in
            self.jsonResponse(status: 200, url: baseURL, body: Data("not json".utf8))
        }

        do {
            _ = try await client.fetchListings()
            Issue.record("expected decoding error to be thrown")
        } catch let error as APIError {
            guard case .decoding = error else {
                Issue.record("expected .decoding, got \(error)")
                return
            }
        }
    }
}
