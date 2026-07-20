import Testing

extension Tag {
    /// Marks the tests that satisfy the assignment's explicit requirement —
    /// "unit tests for sync logic" — so they're easy to spot (and to run in
    /// isolation, via Xcode's Test Navigator or `swift test --filter`)
    /// without cutting the rest of the suite. Everything else exists
    /// because the architecture's protocol seams make it cheap to test,
    /// not because it was asked for.
    @Tag static var coreRequirement: Self
}
