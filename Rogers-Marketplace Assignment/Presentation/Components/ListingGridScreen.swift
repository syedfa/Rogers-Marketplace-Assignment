import SwiftUI

/// Shared feed layout for `HomeView` and `SavedView` — a Marketplace-style
/// 2-column photo grid with search, an optional category rail, and a sync
/// status banner. The two screens differ only in their query and copy.
struct ListingGridScreen: View {
    let title: String
    let favoritesOnly: Bool
    let showCategoryChips: Bool
    let emptyTitle: String
    let emptyMessage: String
    let emptySystemImage: String

    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: ListingGridViewModel?
    @State private var syncStatus: SyncStatusViewModel?
    @State private var selectedListing: Listing?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let viewModel {
                    if showCategoryChips {
                        CategoryChips(selected: Binding(
                            get: { viewModel.selectedCategory },
                            set: { viewModel.selectedCategory = $0 }
                        ))
                    }

                    if viewModel.listings.isEmpty && !viewModel.isLoading {
                        ContentUnavailableView(
                            emptyTitle,
                            systemImage: emptySystemImage,
                            description: Text(emptyMessage)
                        )
                        .padding(.top, 60)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(viewModel.listings) { listing in
                                Button {
                                    selectedListing = listing
                                } label: {
                                    ListingCard(listing: listing) {
                                        viewModel.toggleFavorite(listing)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                }
            }
            .refreshable {
                await viewModel?.refresh()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let syncStatus {
                    SyncStatusBanner(status: syncStatus.status)
                        .animation(.default, value: syncStatus.status)
                }
            }
            .navigationTitle(title)
            .searchable(
                text: Binding(
                    get: { viewModel?.searchText ?? "" },
                    set: { viewModel?.searchText = $0 }
                ),
                prompt: "Search Marketplace"
            )
            .navigationDestination(item: $selectedListing) { listing in
                ListingDetailView(listing: listing)
            }
        }
        .task {
            if viewModel == nil {
                viewModel = ListingGridViewModel(
                    repository: dependencies.repository,
                    syncEngine: dependencies.syncEngine,
                    favoritesOnly: favoritesOnly
                )
                syncStatus = SyncStatusViewModel(syncEngine: dependencies.syncEngine)
            }
            viewModel?.onAppear()
        }
    }
}
