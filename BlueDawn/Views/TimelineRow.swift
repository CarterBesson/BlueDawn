import SwiftUI

struct TimelineRow: View {
    let post: UnifiedPost
    let session: SessionStore
    let onOpenPost: (UnifiedPost) -> Void
    let onOpenProfile: (Network, String) -> Void
    let onTapImage: (UnifiedPost, Int) -> Void
    let onOpenExternalURL: (URL) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundTint: Color {
        // Stronger opacity in dark mode so tint remains visible
        let dark = (colorScheme == .dark)
        switch post.network {
        case .bluesky:
            return Color.blue.opacity(dark ? 0.14 : 0.06)
        case .mastodon:
            return Color.purple.opacity(dark ? 0.14 : 0.06)
        }
    }

    var body: some View {
        // Always show a regular post; temporarily hide thread/reply previews
        HStack(alignment: .top, spacing: 12) {
            Button { onOpenProfile(post.network, post.authorHandle) } label: {
                AvatarCircle(handle: post.authorHandle, url: post.authorAvatarURL)
            }
            .buttonStyle(.plain)

            PostRow(
                post: post,
                showAvatar: false,
                onOpenProfile: onOpenProfile,
                onOpenPost: onOpenPost,
                onTapImage: { tappedPost, idx in onTapImage(tappedPost, idx) },
                onOpenExternalURL: onOpenExternalURL,
                compactPadding: true
            )
            .contentShape(Rectangle())
            .onTapGesture { onOpenPost(post) }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(backgroundTint)
        .overlay(alignment: .bottom) {
            // Small line to separate posts across full row width
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(height: 0.5)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            let long = session.swipeTrailingLong
            let short = session.swipeTrailingShort
            swipeButton(for: long)
            swipeButton(for: short)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            let long = session.swipeLeadingLong
            let short = session.swipeLeadingShort
            swipeButton(for: long)
            swipeButton(for: short)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
    }
}

// MARK: - Swipe helpers
extension TimelineRow {
    @ViewBuilder
    func swipeButton(for action: SessionStore.SwipeAction) -> some View {
        switch action {
        case .none:
            EmptyView()
        case .reply:
            Button {
                Haptics.impact(.light)
                onOpenPost(post)
            } label: { Label(action.label, systemImage: action.systemImage) }
            .tint(.blue)
        case .like:
            Button { Task { await toggleLike() } } label: { Label(labelForLike(), systemImage: symbolForLike()) }
            .tint(.pink)
        case .repost:
            Button { Task { await toggleRepost() } } label: { Label(labelForRepost(), systemImage: "arrow.2.squarepath") }
            .tint(.green)
        case .bookmark:
            if case .mastodon = post.network {
                Button { Task { await toggleBookmark() } } label: { Label(labelForBookmark(), systemImage: symbolForBookmark()) }
                .tint(.yellow)
            } else {
                EmptyView()
            }
        }
    }

    private func labelForLike() -> String { session.state(for: post).isLiked ? "Unlike" : "Like" }
    private func symbolForLike() -> String { session.state(for: post).isLiked ? "heart.fill" : "heart" }
    private func labelForRepost() -> String { session.state(for: post).isReposted ? "Undo Repost" : "Repost" }
    private func labelForBookmark() -> String { session.state(for: post).isBookmarked ? "Remove" : "Bookmark" }
    private func symbolForBookmark() -> String { session.state(for: post).isBookmarked ? "bookmark.fill" : "bookmark" }

    @MainActor private func toggleLike() async {
        let s = session.state(for: post)
        let prevLiked = s.isLiked
        let prevCount = s.likeCount
        let prevRkey = s.bskyLikeRkey
        if s.isLiked {
            Haptics.impact(.rigid)
            withAnimation { session.updateState(for: post.id) { $0.isLiked = false; $0.likeCount = max(0, prevCount - 1) } }
            switch post.network {
            case .bluesky:
                do { try await session.blueskyClient?.unlike(post: post, rkey: prevRkey) } catch {
                    Haptics.notify(.error)
                    withAnimation { session.updateState(for: post.id) { $0.isLiked = prevLiked; $0.likeCount = prevCount } }
                }
            case .mastodon:
                do { try await session.mastodonClient?.unlike(post: post, rkey: nil) } catch {
                    Haptics.notify(.error)
                    withAnimation { session.updateState(for: post.id) { $0.isLiked = prevLiked; $0.likeCount = prevCount } }
                }
            }
            return
        }
        Haptics.impact(.light)
        withAnimation { session.updateState(for: post.id) { $0.isLiked = true; $0.likeCount = prevCount + 1 } }
        switch post.network {
        case .bluesky:
            do {
                let rkey = try await session.blueskyClient?.like(post: post)
                withAnimation { session.updateState(for: post.id) { $0.bskyLikeRkey = rkey ?? prevRkey } }
            } catch {
                Haptics.notify(.error)
                withAnimation { session.updateState(for: post.id) { $0.isLiked = prevLiked; $0.likeCount = prevCount } }
            }
        case .mastodon:
            do { _ = try await session.mastodonClient?.like(post: post) } catch {
                Haptics.notify(.error)
                withAnimation { session.updateState(for: post.id) { $0.isLiked = prevLiked; $0.likeCount = prevCount } }
            }
        }
    }

    @MainActor private func toggleRepost() async {
        let s = session.state(for: post)
        let prev = s.isReposted
        let prevCount = s.repostCount
        let prevRkey = s.bskyRepostRkey
        if s.isReposted {
            Haptics.impact(.rigid)
            withAnimation { session.updateState(for: post.id) { $0.isReposted = false; $0.repostCount = max(0, prevCount - 1) } }
            switch post.network {
            case .bluesky:
                do { try await session.blueskyClient?.unrepost(post: post, rkey: prevRkey) } catch {
                    Haptics.notify(.error)
                    withAnimation { session.updateState(for: post.id) { $0.isReposted = prev; $0.repostCount = prevCount } }
                }
            case .mastodon:
                do { try await session.mastodonClient?.unrepost(post: post, rkey: nil) } catch {
                    Haptics.notify(.error)
                    withAnimation { session.updateState(for: post.id) { $0.isReposted = prev; $0.repostCount = prevCount } }
                }
            }
            return
        }
        Haptics.impact(.light)
        withAnimation { session.updateState(for: post.id) { $0.isReposted = true; $0.repostCount = prevCount + 1 } }
        switch post.network {
        case .bluesky:
            do {
                let rkey = try await session.blueskyClient?.repost(post: post)
                withAnimation { session.updateState(for: post.id) { $0.bskyRepostRkey = rkey ?? prevRkey } }
            } catch {
                Haptics.notify(.error)
                withAnimation { session.updateState(for: post.id) { $0.isReposted = prev; $0.repostCount = prevCount } }
            }
        case .mastodon:
            do { _ = try await session.mastodonClient?.repost(post: post) } catch {
                Haptics.notify(.error)
                withAnimation { session.updateState(for: post.id) { $0.isReposted = prev; $0.repostCount = prevCount } }
            }
        }
    }

    @MainActor private func toggleBookmark() async {
        guard case .mastodon = post.network else { return }
        let prev = session.state(for: post).isBookmarked
        if prev {
            Haptics.impact(.rigid)
            withAnimation { session.updateState(for: post.id) { $0.isBookmarked = false } }
            do { try await session.mastodonClient?.unbookmark(post: post) } catch {
                Haptics.notify(.error)
                withAnimation { session.updateState(for: post.id) { $0.isBookmarked = prev } }
            }
        } else {
            Haptics.impact(.light)
            withAnimation { session.updateState(for: post.id) { $0.isBookmarked = true } }
            do { try await session.mastodonClient?.bookmark(post: post) } catch {
                Haptics.notify(.error)
                withAnimation { session.updateState(for: post.id) { $0.isBookmarked = prev } }
            }
        }
    }
}
