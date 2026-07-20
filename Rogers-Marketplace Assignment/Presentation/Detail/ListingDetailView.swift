import SwiftUI

struct ListingDetailView: View {
    let listing: Listing
    /// Called after the favorite change is persisted, so whichever grid
    /// screen pushed this view can update its own in-memory list in place
    /// instead of waiting for its next sync-driven reload.
    var onFavoriteToggled: ((String, Bool) -> Void)?

    @Environment(\.dependencies) private var dependencies
    @State private var isFavorite: Bool

    init(listing: Listing, onFavoriteToggled: ((String, Bool) -> Void)? = nil) {
        self.listing = listing
        self.onFavoriteToggled = onFavoriteToggled
        _isFavorite = State(initialValue: listing.isFavorite)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                gallery

                VStack(alignment: .leading, spacing: 8) {
                    PriceText(price: listing.price, font: .title2)
                    Text(listing.title)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 6) {
                        Image(systemName: listing.category.symbolName)
                        Text(listing.category.displayName)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if listing.syncState != .synced {
                        Label(
                            listing.syncState == .failed ? "Sync failed — will retry" : "Pending sync",
                            systemImage: listing.syncState == .failed ? "exclamationmark.circle" : "clock"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(listing.syncState == .failed ? .red : .orange)
                    }

                    Divider().padding(.vertical, 4)

                    Text("Description")
                        .font(.headline)
                    Text(listing.description)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isFavorite.toggle()
                    let newValue = isFavorite
                    Task {
                        try? await dependencies.repository.setFavorite(id: listing.id, isFavorite: newValue)
                        onFavoriteToggled?(listing.id, newValue)
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                }
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: listing.title)
            }
        }
    }

    @ViewBuilder
    private var gallery: some View {
        if listing.imageURLs.isEmpty {
            CachedThumbnailView(urlString: nil, cornerRadius: 0)
                .frame(height: 320)
        } else {
            TabView {
                ForEach(listing.imageURLs, id: \.self) { url in
                    CachedThumbnailView(urlString: url, cornerRadius: 0)
                }
            }
            .tabViewStyle(.page)
            .frame(height: 320)
        }
    }
}
