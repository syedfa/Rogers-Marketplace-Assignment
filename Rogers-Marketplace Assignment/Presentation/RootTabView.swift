import SwiftUI

struct RootTabView: View {
    private enum Tab: Hashable {
        case home, saved, sell, settings
    }

    @State private var selectedTab: Tab = .home
    @State private var showCreateListing = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "storefront") }
                .tag(Tab.home)
            SavedView()
                .tabItem { Label("Saved", systemImage: "heart") }
                .tag(Tab.saved)
            // Sell has no real tab content — selecting it presents
            // CreateListingView as a modal instead. The placeholder is only
            // ever on screen for the instant before the sheet covers it;
            // reverting `selectedTab` back to `.home` happens on dismiss,
            // not synchronously on selection (fighting the tab bar's own
            // selection animation mid-transition left it visually stuck on
            // "Sell" even after the bound value had been reverted).
            Color.clear
                .tabItem { Label("Sell", systemImage: "plus.circle.fill") }
                .tag(Tab.sell)
                .onAppear { showCreateListing = true }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .sheet(
            isPresented: $showCreateListing,
            onDismiss: { selectedTab = .home },
            content: { CreateListingView() }
        )
    }
}
