import SwiftUI

/// Marketplace-style grid cell: edge-to-edge photo, price bold above the
/// title, a heart overlay to favorite, and a small pending/failed badge
/// when the listing hasn't synced yet.
struct ListingCard: View {
    let listing: Listing
    var onToggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                CachedThumbnailView(urlString: listing.imageURLs.first, cornerRadius: 12)
                    .aspectRatio(1, contentMode: .fit)

                Button(action: onToggleFavorite) {
                    Image(systemName: listing.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .padding(6)
                .accessibilityLabel(listing.isFavorite ? "Remove from favorites" : "Add to favorites")

                if listing.syncState != .synced {
                    VStack {
                        Spacer()
                        HStack {
                            syncBadge
                            Spacer()
                        }
                    }
                    .padding(6)
                }
            }

            PriceText(price: listing.price, font: .subheadline)
            Text(listing.title)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(listing.category.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var syncBadge: some View {
        Image(systemName: listing.syncState == .failed ? "exclamationmark.circle.fill" : "clock.fill")
            .font(.caption2)
            .foregroundStyle(listing.syncState == .failed ? .red : .orange)
            .padding(5)
            .background(.thinMaterial, in: Circle())
    }
}
