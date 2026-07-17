import SwiftUI

struct HomeView: View {
    var body: some View {
        ListingGridScreen(
            title: "Marketplace",
            favoritesOnly: false,
            showCategoryChips: true,
            emptyTitle: "No Listings Yet",
            emptyMessage: "Listings you create will show up here, even offline.",
            emptySystemImage: "storefront"
        )
    }
}
