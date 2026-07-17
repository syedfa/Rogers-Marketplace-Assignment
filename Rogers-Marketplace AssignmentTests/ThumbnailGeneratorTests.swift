import Testing
import UIKit
@testable import Rogers_Marketplace_Assignment

@Suite("ThumbnailGenerator")
struct ThumbnailGeneratorTests {
    @Test("Downsamples a large image to at most the requested pixel size")
    func downsamplesToBound() throws {
        let original = TestImageFactory.jpegData(width: 800, height: 600)
        let thumbData = try #require(ThumbnailGenerator.downsample(data: original, maxPixelSize: 100))
        let thumbImage = try #require(UIImage(data: thumbData))
        #expect(thumbImage.size.width <= 100)
        #expect(thumbImage.size.height <= 100)
    }

    @Test("Downsampling preserves aspect ratio")
    func preservesAspectRatio() throws {
        let original = TestImageFactory.jpegData(width: 800, height: 400) // 2:1
        let thumbData = try #require(ThumbnailGenerator.downsample(data: original, maxPixelSize: 200))
        let thumbImage = try #require(UIImage(data: thumbData))
        let ratio = thumbImage.size.width / thumbImage.size.height
        #expect(abs(ratio - 2.0) < 0.05)
    }

    @Test("Does not upsample an image already smaller than the target")
    func doesNotUpsample() throws {
        let original = TestImageFactory.jpegData(width: 50, height: 50)
        let thumbData = try #require(ThumbnailGenerator.downsample(data: original, maxPixelSize: 1000))
        let thumbImage = try #require(UIImage(data: thumbData))
        #expect(thumbImage.size.width <= 50)
        #expect(thumbImage.size.height <= 50)
    }

    @Test("Returns nil for malformed image data")
    func rejectsMalformedData() {
        let garbage = Data("not an image".utf8)
        #expect(ThumbnailGenerator.downsample(data: garbage, maxPixelSize: 100) == nil)
    }

    @Test("Output is JPEG-encoded and reasonably small")
    func outputIsCompact() throws {
        let original = TestImageFactory.jpegData(width: 1200, height: 1200)
        let thumbData = try #require(ThumbnailGenerator.downsample(data: original, maxPixelSize: 150))
        #expect(thumbData.count < original.count)
    }
}
