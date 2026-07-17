import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class CreateListingViewModel {
    var title = ""
    var descriptionText = ""
    var priceText = ""
    var category: Category = .other
    var pickedImages: [UIImage] = []
    private(set) var fieldErrors: [ValidationField: String] = [:]
    private(set) var isPublishing = false
    private(set) var didPublish = false

    private let repository: ListingRepositoryProtocol
    private let validator = ListingValidator()

    /// Cap on the longest edge of an embedded photo. JSON Server has no
    /// multipart upload, so images travel as base64 inside the listing's
    /// JSON payload — keeping this modest keeps that payload (and the
    /// SwiftData row storing it) reasonable.
    private static let maxEmbeddedImagePixelSize = 1200

    init(repository: ListingRepositoryProtocol) {
        self.repository = repository
    }

    func removeImage(at index: Int) {
        guard pickedImages.indices.contains(index) else { return }
        pickedImages.remove(at: index)
    }

    func publish() async {
        let (errors, price) = validator.validate(
            title: title,
            description: descriptionText,
            priceText: priceText,
            imageCount: pickedImages.count
        )
        fieldErrors = Dictionary(uniqueKeysWithValues: errors.map { ($0.field, $0.message) })
        guard errors.isEmpty, let price else { return }

        isPublishing = true
        defer { isPublishing = false }

        let imageDataURLs = pickedImages.compactMap { image -> String? in
            guard let jpeg = image.jpegData(compressionQuality: 0.85),
                  let thumbnail = ThumbnailGenerator.downsample(
                      data: jpeg, maxPixelSize: Self.maxEmbeddedImagePixelSize
                  ) else {
                return nil
            }
            return "data:image/jpeg;base64,\(thumbnail.base64EncodedString())"
        }

        let listing = Listing(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            price: price,
            category: category,
            imageURLs: imageDataURLs
        )

        try? await repository.create(listing)
        didPublish = true
    }
}
