import Testing
import Foundation
import UIKit
@testable import Rogers_Marketplace_Assignment

@Suite("ImageCache")
struct ImageCacheTests {
    func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageCacheTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func makeCache(
        directory: URL? = nil,
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> ImageCache {
        ImageCache(
            store: ImageStore(directory: directory ?? makeTempDirectory()),
            session: StubURLProtocol.makeSession(handler: handler)
        )
    }

    @Test("Decodes a data: URL without touching the network")
    func decodesDataURLWithoutNetwork() async throws {
        let cache = makeCache { _ in throw URLError(.notConnectedToInternet) }
        let url = try #require(URL(string: TestImageFactory.dataURLString(width: 300, height: 300)))

        let thumb = try await cache.thumbnail(for: url, targetSize: CGSize(width: 100, height: 100))

        #expect(!thumb.isEmpty)
    }

    @Test("A repeated request for the same URL and size hits the in-memory cache, not the network")
    func memoryHitAvoidsRefetch() async throws {
        let fetchCount = Counter()
        let imageData = TestImageFactory.jpegData(width: 400, height: 400)
        let cache = makeCache { request in
            fetchCount.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, imageData)
        }
        let url = URL(string: "http://localhost:3000/images/a.jpg")!

        _ = try await cache.thumbnail(for: url, targetSize: CGSize(width: 100, height: 100))
        _ = try await cache.thumbnail(for: url, targetSize: CGSize(width: 100, height: 100))

        #expect(fetchCount.value == 1)
    }

    @Test("A disk hit (fresh in-memory cache, same store directory) avoids re-fetching from the network")
    func diskHitAvoidsRefetch() async throws {
        let fetchCount = Counter()
        let imageData = TestImageFactory.jpegData(width: 400, height: 400)
        let directory = makeTempDirectory()
        let url = URL(string: "http://localhost:3000/images/a.jpg")!
        let handler: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) = { request in
            fetchCount.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, imageData)
        }

        let firstCache = makeCache(directory: directory, handler: handler)
        _ = try await firstCache.thumbnail(for: url, targetSize: CGSize(width: 100, height: 100))

        let secondCache = makeCache(directory: directory, handler: handler)
        _ = try await secondCache.thumbnail(for: url, targetSize: CGSize(width: 100, height: 100))

        #expect(fetchCount.value == 1)
    }

    @Test("clearCache empties both the disk usage counter and future lookups re-fetch")
    func clearCacheResetsDiskUsage() async throws {
        let imageData = TestImageFactory.jpegData(width: 400, height: 400)
        let cache = makeCache { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, imageData)
        }
        let url = URL(string: "http://localhost:3000/images/a.jpg")!
        _ = try await cache.thumbnail(for: url, targetSize: CGSize(width: 100, height: 100))
        #expect(await cache.currentDiskUsageBytes > 0)

        await cache.clearCache()

        #expect(await cache.currentDiskUsageBytes == 0)
    }

    @Test("Thumbnails are bounded by the requested target size")
    func thumbnailsAreBounded() async throws {
        let cache = makeCache { _ in throw URLError(.notConnectedToInternet) }
        let url = try #require(URL(string: TestImageFactory.dataURLString(width: 1000, height: 1000)))

        let thumbData = try await cache.thumbnail(for: url, targetSize: CGSize(width: 80, height: 80))
        let thumbImage = try #require(UIImage(data: thumbData))

        #expect(thumbImage.size.width <= 80)
        #expect(thumbImage.size.height <= 80)
    }
}
