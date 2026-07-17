import SwiftUI

/// Loads a listing image through `ImageCache`, requesting exactly the pixel
/// size the cell will render at (point size × display scale) so ImageIO
/// never decodes more pixels than the screen can show.
struct CachedThumbnailView: View {
    let urlString: String?
    var cornerRadius: CGFloat = 8

    @Environment(\.dependencies) private var dependencies
    @Environment(\.displayScale) private var displayScale
    @State private var uiImage: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .task(id: taskID(size: proxy.size)) {
                await load(size: proxy.size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .overlay {
                Image(systemName: failed ? "photo.badge.exclamationmark" : "photo")
                    .foregroundStyle(.tertiary)
            }
    }

    private func taskID(size: CGSize) -> String {
        "\(urlString ?? "")-\(Int(size.width * displayScale))"
    }

    private func load(size: CGSize) async {
        guard let urlString, let url = URL(string: urlString), size.width > 0 else {
            failed = urlString != nil
            return
        }
        let pixelSize = CGSize(width: size.width * displayScale, height: size.height * displayScale)
        do {
            let data = try await dependencies.imageCache.thumbnail(for: url, targetSize: pixelSize)
            uiImage = UIImage(data: data)
            failed = uiImage == nil
        } catch {
            failed = true
        }
    }
}
