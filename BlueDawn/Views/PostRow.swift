import SwiftUI

struct PostRow: View {
    let post: UnifiedPost
    var showAvatar: Bool = true
    var onOpenProfile: ((Network, String) -> Void)? = nil
    // New: notify parent when an image is tapped (post + index within post.media)
    var onTapImage: ((UnifiedPost, Int) -> Void)? = nil

    @ViewBuilder private var shareBanner: some View {
        if post.isRepostOrBoost, let name = post.boostedByDisplayName ?? post.boostedByHandle {
            HStack(spacing: 6) {
                Image(systemName: "arrow.2.squarepath")
                Button {
                    let handle = post.boostedByHandle ?? post.authorHandle
                    onOpenProfile?(post.network, handle)
                } label: {
                    Text("\(bannerVerb) \(name)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var crossPostBadge: some View {
        if let alts = post.crossPostAlternates, !alts.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "link")
                if alts.keys.contains(where: { if case .bluesky = $0 { return true } else { return false } }) {
                    Image(systemName: "cloud")
                }
                if alts.keys.contains(where: { if case .mastodon = $0 { return true } else { return false } }) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                }
                Text("Also on \(altNames(alts))")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Also posted on \(altNames(alts))")
        }
    }

    private func altNames(_ alts: [Network: String]) -> String {
        var names: [String] = []
        if alts.keys.contains(where: { if case .bluesky = $0 { return true } else { return false } }) { names.append("Bluesky") }
        if alts.keys.contains(where: { if case .mastodon = $0 { return true } else { return false } }) { names.append("Mastodon") }
        return names.joined(separator: " & ")
    }

    private var bannerVerb: String {
        switch post.network {
        case .bluesky: return "Reposted by"
        case .mastodon: return "Boosted by"
        }
    }

    // Subtle network-specific background tint
    private var backgroundTint: Color {
        switch post.network {
        case .bluesky:
            return Color.blue.opacity(0.06)
        case .mastodon:
            return Color.purple.opacity(0.06)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            shareBanner
            crossPostBadge
            header
            content
            if !post.media.isEmpty { mediaStrip }
            actionBar
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(backgroundTint)
        // Thin separator line at the bottom to delineate posts
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(height: 0.5)
        }
        // Handle taps on links inside attributed text for mentions/user profiles
        .environment(\.openURL, OpenURLAction { url in
            handleOpenURL(url)
        })
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
                ForEach(Array(post.media.enumerated()), id: \.offset) { idx, m in
                    Button {
                        onTapImage?(post, idx)
                    } label: {
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(m.altText ?? "Image")
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

private extension PostRow {
    func handleOpenURL(_ url: URL) -> OpenURLAction.Result {
        // Bluesky internal mention links
        if url.scheme == "bluesky" && url.host == "profile" {
            let comps = url.pathComponents.filter { $0 != "/" }
            if let handle = comps.first, !handle.isEmpty {
                onOpenProfile?(.bluesky, handle)
                return .handled
            }
        }

        // Mastodon profile links like https://instance/@user
        if let scheme = url.scheme, (scheme == "https" || scheme == "http"),
           let host = url.host {
            let path = url.path
            if path.hasPrefix("/@") {
                let username = String(path.dropFirst(2)) // drop "/@"
                let handle = username.isEmpty ? "" : "\(username)@\(host)"
                if !handle.isEmpty { onOpenProfile?(.mastodon(instance: host), handle); return .handled }
            }
            // Bluesky web profile links: https://bsky.app/profile/<handle>
            if host == "bsky.app" && path.hasPrefix("/profile/") {
                let handle = String(path.dropFirst("/profile/".count))
                if !handle.isEmpty { onOpenProfile?(.bluesky, handle); return .handled }
            }
        }

        return .systemAction
    }
}
