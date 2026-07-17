import SwiftUI

private struct BannerPresentation {
    let text: String
    let systemImage: String
    let tint: Color
}

struct SyncStatusBanner: View {
    let status: SyncStatus

    var body: some View {
        if let presentation {
            HStack(spacing: 6) {
                if case .syncing = status.phase {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: presentation.systemImage)
                }
                Text(presentation.text)
                Spacer(minLength: 0)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(presentation.tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(presentation.tint.opacity(0.12))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var presentation: BannerPresentation? {
        switch status.phase {
        case .idle, .synced:
            guard status.pendingCount > 0 else { return nil }
            let noun = status.pendingCount == 1 ? "change" : "changes"
            return BannerPresentation(
                text: "\(status.pendingCount) \(noun) waiting to sync",
                systemImage: "arrow.triangle.2.circlepath",
                tint: .orange
            )
        case .offline:
            return BannerPresentation(text: "Offline — changes will sync automatically", systemImage: "wifi.slash", tint: .secondary)
        case .syncing:
            return BannerPresentation(text: "Syncing…", systemImage: "arrow.triangle.2.circlepath", tint: .blue)
        case .failed:
            return BannerPresentation(text: "Sync failed — will retry", systemImage: "exclamationmark.triangle", tint: .red)
        }
    }
}
