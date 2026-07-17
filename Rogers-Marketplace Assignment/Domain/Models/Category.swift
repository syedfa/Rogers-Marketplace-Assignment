import Foundation

/// Fixed marketplace categories. A closed set keeps the Sell form and
/// category chips in sync without needing a server round-trip.
enum Category: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case electronics
    case furniture
    case clothing
    case vehicles
    case homeAndGarden = "home_and_garden"
    case toys
    case sports
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .electronics: return "Electronics"
        case .furniture: return "Furniture"
        case .clothing: return "Clothing"
        case .vehicles: return "Vehicles"
        case .homeAndGarden: return "Home & Garden"
        case .toys: return "Toys & Games"
        case .sports: return "Sporting Goods"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .electronics: return "tv"
        case .furniture: return "sofa"
        case .clothing: return "tshirt"
        case .vehicles: return "car"
        case .homeAndGarden: return "leaf"
        case .toys: return "gamecontroller"
        case .sports: return "sportscourt"
        case .other: return "shippingbox"
        }
    }
}
