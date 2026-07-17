import SwiftUI

struct SavedView: View {
    var body: some View {
        ListingGridScreen(
            title: "Saved",
            favoritesOnly: true,
            showCategoryChips: false,
            emptyTitle: "No Saved Items",
            emptyMessage: "Tap the heart on any listing to save it here.",
            emptySystemImage: "heart"
        )
    }
}
