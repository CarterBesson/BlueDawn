import SwiftUI

struct AvatarView: View {
    let url: URL?
    let fallbackText: String
    let networkIcon: String? // e.g., "cloud" for Bluesky, "dot.radiowaves.left.and.right" for Mastodon
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Circle().fill(Color.secondary.opacity(0.15))
                                .overlay(ProgressView().scaleEffect(0.7))
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            if let networkIcon {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Image(systemName: networkIcon)
                        .font(.system(size: 10, weight: .semibold))
                }
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
                .offset(x: 2, y: 2)
            }
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.secondary.opacity(0.2))
            .overlay(
                Text(String(fallbackText.uppercased().prefix(1)))
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.secondary)
            )
    }
}
