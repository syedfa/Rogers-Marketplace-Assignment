import UIKit

enum TestImageFactory {
    static func jpegData(width: CGFloat, height: CGFloat, color: UIColor = .systemBlue) -> Data {
        // Force scale = 1 so the requested width/height land exactly in the
        // encoded pixel dimensions — UIGraphicsImageRenderer otherwise
        // defaults to the device's Retina scale (e.g. 3x on current
        // simulators), silently tripling the fixture's actual pixel size.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    static func dataURLString(width: CGFloat, height: CGFloat, color: UIColor = .systemBlue) -> String {
        "data:image/jpeg;base64,\(jpegData(width: width, height: height, color: color).base64EncodedString())"
    }
}

/// A tiny mutable counter safe to capture in `@Sendable` closures used from
/// a single serialized test at a time.
final class Counter: @unchecked Sendable {
    private(set) var value = 0
    func increment() { value += 1 }
}
