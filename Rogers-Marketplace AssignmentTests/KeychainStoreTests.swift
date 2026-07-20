import Testing
import Foundation
@testable import Rogers_Marketplace_Assignment

@Suite("KeychainStore", .serialized)
struct KeychainStoreTests {
    // A unique service per test run avoids collisions with any real app data
    // and lets tests run in isolation from each other.
    func makeStore() -> KeychainStore {
        KeychainStore(service: "ca.cybermedia.RogersMarketplace.tests.\(UUID().uuidString)")
    }

    @Test("Set then get round-trips the value")
    func setThenGet() throws {
        let store = makeStore()
        try store.set("super-secret-token", forKey: "apiToken")
        #expect(try store.get("apiToken") == "super-secret-token")
    }

    @Test("Get for a missing key returns nil")
    func missingKeyReturnsNil() throws {
        let store = makeStore()
        #expect(try store.get("doesNotExist") == nil)
    }

    @Test("Setting the same key twice overwrites the previous value")
    func overwritesExistingValue() throws {
        let store = makeStore()
        try store.set("first", forKey: "apiToken")
        try store.set("second", forKey: "apiToken")
        #expect(try store.get("apiToken") == "second")
    }

    @Test("Delete removes the value")
    func deleteRemovesValue() throws {
        let store = makeStore()
        try store.set("value", forKey: "apiToken")
        try store.delete("apiToken")
        #expect(try store.get("apiToken") == nil)
    }

    @Test("Delete on a missing key does not throw")
    func deleteMissingKeyIsNoop() throws {
        let store = makeStore()
        try store.delete("neverSet")
    }

    @Test("Different keys under the same service are independent")
    func independentKeys() throws {
        let store = makeStore()
        try store.set("token-value", forKey: "apiToken")
        try store.set("url-value", forKey: "serverURL")
        #expect(try store.get("apiToken") == "token-value")
        #expect(try store.get("serverURL") == "url-value")
    }
}
