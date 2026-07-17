import Foundation
import CoreGraphics

enum ImageCacheError: Error, Sendable {
    case decodingFailed
    case invalidDataURL
}

/// Three-tier thumbnail cache: in-memory `NSCache` (fast, cost-limited,
/// evicted under memory pressure) → disk (`ImageStore`, survives relaunch)
/// → network/data-URL decode (slowest, only on a full miss).
///
/// An actor so concurrent requests for the same URL from many visible grid
/// cells serialize through one cache instance without extra locking.
actor ImageCache: ImageCaching {
    private let memoryCache: NSCache<NSString, NSData>
    private let store: ImageStore
    private let session: URLSession

    init(store: ImageStore, session: URLSession = .shared, costLimitBytes: Int = 50 * 1024 * 1024) {
        self.store = store
        self.session = session
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = costLimitBytes
        self.memoryCache = cache
    }

    /// - Parameter targetSize: the desired thumbnail size **in pixels**
    ///   (i.e. already multiplied by the display scale by the caller).
    func thumbnail(for url: URL, targetSize: CGSize) async throws -> Data {
        let maxPixelSize = Int(max(targetSize.width, targetSize.height))
        let key = cacheKey(url: url, maxPixelSize: maxPixelSize)

        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached as Data
        }
        if let diskData = store.readThumbnail(key: key) {
            memoryCache.setObject(diskData as NSData, forKey: key as NSString, cost: diskData.count)
            return diskData
        }

        let sourceData = try await fetchSourceData(url: url)
        guard let thumbnail = ThumbnailGenerator.downsample(data: sourceData, maxPixelSize: maxPixelSize) else {
            throw ImageCacheError.decodingFailed
        }
        try? store.writeThumbnail(thumbnail, key: key)
        memoryCache.setObject(thumbnail as NSData, forKey: key as NSString, cost: thumbnail.count)
        return thumbnail
    }

    func clearCache() async {
        memoryCache.removeAllObjects()
        try? store.removeAll()
    }

    var currentDiskUsageBytes: Int {
        store.totalSizeBytes()
    }

    private func fetchSourceData(url: URL) async throws -> Data {
        if url.scheme == "data" {
            return try decodeDataURL(url)
        }
        let (data, _) = try await session.data(from: url)
        return data
    }

    private func cacheKey(url: URL, maxPixelSize: Int) -> String {
        "\(url.absoluteString)-\(maxPixelSize)"
    }

    /// Parses `data:<mime>;base64,<payload>` URLs. `URL` itself won't parse
    /// these into components, so this is done directly on the string.
    private func decodeDataURL(_ url: URL) throws -> Data {
        let string = url.absoluteString
        guard let commaIndex = string.firstIndex(of: ",") else { throw ImageCacheError.invalidDataURL }
        let base64 = String(string[string.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64) else { throw ImageCacheError.invalidDataURL }
        return data
    }
}
