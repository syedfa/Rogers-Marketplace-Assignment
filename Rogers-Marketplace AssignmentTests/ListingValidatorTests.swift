import Testing
import Foundation
@testable import Rogers_Marketplace_Assignment

@Suite("ListingValidator")
struct ListingValidatorTests {
    let validator = ListingValidator()

    @Test("Accepts a title within bounds")
    func validTitle() {
        #expect(validator.validateTitle("Vintage Leather Sofa") == nil)
    }

    @Test("Rejects an empty or whitespace-only title")
    func emptyTitle() {
        #expect(validator.validateTitle("") != nil)
        #expect(validator.validateTitle("   ") != nil)
    }

    @Test("Rejects a title that is too short")
    func tooShortTitle() {
        #expect(validator.validateTitle("ab") != nil)
    }

    @Test("Rejects a title that is too long")
    func tooLongTitle() {
        let longTitle = String(repeating: "a", count: 101)
        #expect(validator.validateTitle(longTitle) != nil)
    }

    @Test("Accepts a description within bounds")
    func validDescription() {
        #expect(validator.validateDescription("A gently used bicycle, well maintained.") == nil)
    }

    @Test("Rejects an empty description")
    func emptyDescription() {
        #expect(validator.validateDescription("") != nil)
        #expect(validator.validateDescription("   ") != nil)
    }

    @Test("Rejects a description that is too long")
    func tooLongDescription() {
        let longDescription = String(repeating: "a", count: 2001)
        #expect(validator.validateDescription(longDescription) != nil)
    }

    @Test("Parses a plain decimal price")
    func parsesPlainPrice() {
        switch validator.validatePrice("12.50") {
        case .success(let value): #expect(value == Decimal(string: "12.50"))
        case .failure: Issue.record("expected success")
        }
    }

    @Test("Parses a price with a leading currency symbol")
    func parsesPriceWithCurrencySymbol() {
        switch validator.validatePrice("$45") {
        case .success(let value): #expect(value == 45)
        case .failure: Issue.record("expected success")
        }
    }

    @Test("Rejects an empty price")
    func rejectsEmptyPrice() {
        switch validator.validatePrice("") {
        case .success: Issue.record("expected failure")
        case .failure(let error): #expect(error.field == .price)
        }
    }

    @Test("Rejects a price with thousands separators as ambiguous")
    func rejectsAmbiguousSeparators() {
        switch validator.validatePrice("12,50,0") {
        case .success: Issue.record("expected failure")
        case .failure: break
        }
    }

    @Test("Rejects a negative price")
    func rejectsNegativePrice() {
        switch validator.validatePrice("-5") {
        case .success: Issue.record("expected failure")
        case .failure: break
        }
    }

    @Test("Rejects a zero price")
    func rejectsZeroPrice() {
        switch validator.validatePrice("0") {
        case .success: Issue.record("expected failure")
        case .failure: break
        }
    }

    @Test("Rejects a non-numeric price")
    func rejectsNonNumericPrice() {
        switch validator.validatePrice("free!!") {
        case .success: Issue.record("expected failure")
        case .failure: break
        }
    }

    @Test("Rejects a price above the maximum")
    func rejectsPriceAboveMax() {
        switch validator.validatePrice("9999999") {
        case .success: Issue.record("expected failure")
        case .failure: break
        }
    }

    @Test("Accepts an image count within bounds")
    func validImageCount() {
        #expect(validator.validateImageCount(1) == nil)
        #expect(validator.validateImageCount(10) == nil)
    }

    @Test("Rejects zero images")
    func rejectsZeroImages() {
        #expect(validator.validateImageCount(0) != nil)
    }

    @Test("Rejects too many images")
    func rejectsTooManyImages() {
        #expect(validator.validateImageCount(11) != nil)
    }

    @Test("validate(...) aggregates all field errors at once")
    func aggregatesAllErrors() {
        let (errors, price) = validator.validate(title: "", description: "", priceText: "", imageCount: 0)
        #expect(errors.count == 4)
        #expect(price == nil)
    }

    @Test("validate(...) returns the parsed price alongside an empty error list when everything is valid")
    func aggregateSuccessReturnsParsedPrice() {
        let (errors, price) = validator.validate(
            title: "Vintage Leather Sofa",
            description: "A gently used sofa in great condition.",
            priceText: "199.99",
            imageCount: 2
        )
        #expect(errors.isEmpty)
        #expect(price == Decimal(string: "199.99"))
    }
}
