import Foundation

enum ValidationField: String, Sendable {
    case title, description, price, category, images
}

struct ValidationError: Error, Equatable, Sendable {
    let field: ValidationField
    let message: String
}

/// Pure validation rules for listing creation/editing, enforced before
/// anything is written to the repository. Kept dependency-free so it can be
/// reused by both the Sell form and (if needed) server-mirrored checks.
struct ListingValidator: Sendable {
    static let titleRange = 3...100
    static let descriptionRange = 1...2000
    static let maxPrice: Decimal = 1_000_000
    static let maxImageCount = 10

    func validateTitle(_ title: String) -> ValidationError? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ValidationError(field: .title, message: "Title is required.")
        }
        guard Self.titleRange.contains(trimmed.count) else {
            return ValidationError(
                field: .title,
                message: "Title must be between \(Self.titleRange.lowerBound) and \(Self.titleRange.upperBound) characters."
            )
        }
        return nil
    }

    func validateDescription(_ description: String) -> ValidationError? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ValidationError(field: .description, message: "Description is required.")
        }
        guard Self.descriptionRange.contains(trimmed.count) else {
            return ValidationError(
                field: .description,
                message: "Description must be \(Self.descriptionRange.upperBound) characters or fewer."
            )
        }
        return nil
    }

    /// Parses and validates a user-entered price string. Accepts a plain
    /// decimal with an optional leading currency symbol; rejects thousands
    /// separators to avoid ambiguous locale parsing (e.g. "12,50,0").
    func validatePrice(_ text: String) -> Result<Decimal, ValidationError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "$"))
        guard !trimmed.isEmpty else {
            return .failure(ValidationError(field: .price, message: "Price is required."))
        }
        guard trimmed.filter({ $0 == "." }).count <= 1,
              trimmed.allSatisfy({ $0.isNumber || $0 == "." }),
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            return .failure(ValidationError(field: .price, message: "Enter a valid price, e.g. 12.50."))
        }
        guard value > 0 else {
            return .failure(ValidationError(field: .price, message: "Price must be greater than zero."))
        }
        guard value <= Self.maxPrice else {
            return .failure(ValidationError(field: .price, message: "Price must be \(Self.maxPrice) or less."))
        }
        return .success(value)
    }

    func validateImageCount(_ count: Int) -> ValidationError? {
        guard count > 0 else {
            return ValidationError(field: .images, message: "Add at least one photo.")
        }
        guard count <= Self.maxImageCount else {
            return ValidationError(field: .images, message: "You can attach up to \(Self.maxImageCount) photos.")
        }
        return nil
    }

    /// Validates every field, returning all failures (not just the first)
    /// so the Sell form can highlight every invalid field at once.
    func validate(
        title: String,
        description: String,
        priceText: String,
        imageCount: Int
    ) -> (errors: [ValidationError], price: Decimal?) {
        var errors: [ValidationError] = []
        if let error = validateTitle(title) { errors.append(error) }
        if let error = validateDescription(description) { errors.append(error) }
        if let error = validateImageCount(imageCount) { errors.append(error) }

        var parsedPrice: Decimal?
        switch validatePrice(priceText) {
        case .success(let value): parsedPrice = value
        case .failure(let error): errors.append(error)
        }
        return (errors, parsedPrice)
    }
}
