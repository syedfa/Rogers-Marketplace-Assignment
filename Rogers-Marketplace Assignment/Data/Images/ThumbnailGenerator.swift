import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downsamples image bytes using ImageIO, which decodes directly at the
/// target size instead of decoding the full-resolution image into memory
/// first. This is the single biggest lever for keeping the 200-item grid's
/// memory footprint bounded.
enum ThumbnailGenerator {
    static func downsample(
        data: Data,
        maxPixelSize: Int,
        compressionQuality: CGFloat = 0.7
    ) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        let destinationOptions = [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, destinationOptions)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
