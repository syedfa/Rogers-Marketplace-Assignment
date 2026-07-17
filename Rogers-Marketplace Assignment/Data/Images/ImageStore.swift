import Foundation
import CryptoKit

/// Disk-backed thumbnail cache under the app's Caches directory. `Caches`
/// (rather than `Documents`) is deliberate: the OS is free to purge it
/// under storage pressure, and thumbnails are cheaply regenerable from the
/// network, so nothing of value is lost.
struct ImageStore: Sendable {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func defaultDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("ThumbnailCache", isDirectory: true)
    }

    func readThumbnail(key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    func writeThumbnail(_ data: Data, key: String) throws {
        try data.write(to: fileURL(for: key), options: .atomic)
    }

    func removeAll() throws {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files {
            try FileManager.default.removeItem(at: file)
        }
    }

    func totalSizeBytes() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + size
        }
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key.stableCacheFileName, isDirectory: false)
    }
}

extension String {
    /// A stable (cross-launch), filesystem-safe cache key derived from an
    /// arbitrary string such as `"<url>-<maxPixelSize>"`.
    var stableCacheFileName: String {
        let digest = SHA256.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
