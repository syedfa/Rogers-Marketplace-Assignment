import Foundation

enum APIError: Error, Equatable, Sendable {
    case invalidURL
    case transport(String)
    case clientError(status: Int, body: String)
    case serverError(status: Int, body: String)
    case decoding(String)
}

/// Thin abstraction over URLSession so `SyncEngine` and ViewModels can be
/// tested against a fake instead of hitting the network.
///
/// Image bytes are not uploaded through a separate endpoint: JSON Server
/// (the mock backend) has no multipart upload support, so photos are
/// downsampled and embedded as base64 `data:` URLs directly inside
/// `Listing.imageURLs` before the listing is created/updated. A production
/// backend would swap this for presigned-URL or multipart uploads without
/// changing this protocol's shape.
protocol APIClientProtocol: Sendable {
    func fetchListings() async throws -> [Listing]
    func createListing(_ listing: Listing) async throws -> Listing
    func updateListing(_ listing: Listing) async throws -> Listing
}
