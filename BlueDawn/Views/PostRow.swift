import SwiftUI

struct PostRow: View {
    let post: UnifiedPost
    var showAvatar: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
            if !post.media.isEmpty { mediaStrip }
            actionBar
        }
        .padding(.vertical, 8)
    }

    // MARK: - Header
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if showAvatar {
                AvatarView(
                    url: post.authorAvatarURL,
                    fallbackText: post.authorHandle,
                    networkIcon: networkIconName,
                    size: 44
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("@\(post.authorHandle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: networkIconName ?? "questionmark.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(relativeDate(post.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Content
    private var content: some View {
        Text(post.text)
            .font(.body)
            .textSelection(.enabled)
    }

    // MARK: - Media
    private var mediaStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(Array(post.media.enumerated()), id: \.offset) { _, m in
                    AsyncImage(url: m.url) { phase in
                        switch phase {
                        case .empty:
                            Rectangle().fill(Color.secondary.opacity(0.1))
                                .overlay(ProgressView())
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Rectangle().fill(Color.secondary.opacity(0.15))
                                .overlay(Image(systemName: "photo").font(.title3))
                        @unknown default:
                            Rectangle().fill(Color.secondary.opacity(0.15))
                        }
                    }
                    .frame(width: 160, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                    )
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Action bar (icon-only, optional counts)
    private var actionBar: some View {
        HStack(spacing: 22) {
            action(symbol: "bubble.left",      count: post.counts.replies,        label: "Reply")
            action(symbol: "arrow.2.squarepath", count: post.counts.boostsReposts, label: "Repost")
            action(symbol: "heart",            count: post.counts.favLikes,       label: "Like")
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
        .buttonStyle(.plain)
    }

    private func action(symbol: String, count: Int?, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .accessibilityLabel(label)
            if let s = Formatters.shortCount(count) {
                Text(s).accessibilityHidden(true)
            }
        }
    }

    // MARK: - Helpers
    private var displayName: String {
        post.authorDisplayName?.isEmpty == false ? post.authorDisplayName! : post.authorHandle
    }

    private var networkIconName: String? {
        switch post.network {
        case .bluesky: return "cloud"
        case .mastodon: return "dot.radiowaves.left.and.right"
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
