import SwiftUI

struct PostDetailView: View {
    @Environment(SessionStore.self) private var session
    let post: UnifiedPost
    @State var viewModel: ThreadViewModel
    // Shared interaction state is kept in SessionStore; no local state needed
    @State private var initialPosition: String? = "focusedPost"
    @State private var imageViewer: ImageViewerState? = nil
    @State private var profileRoute: ProfileRoute? = nil
    @State private var safariURL: URL? = nil
    @State private var postSelection: UnifiedPost? = nil

    private struct ProfileRoute: Identifiable, Hashable {
        let id = UUID()
        let network: Network
        let handle: String
    }

    init(post: UnifiedPost, viewModel: ThreadViewModel) {
        self.post = post
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {

                // Ancestor context ABOVE the focused post
                if !viewModel.ancestors.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("In reply to")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)

                        ForEach(viewModel.ancestors, id: \.id) { anc in
                            HStack(alignment: .top, spacing: 12) {
                                // Avatar → Profile
                                NavigationLink {
                                    ProfileView(network: anc.network, handle: anc.authorHandle, session: session)
                                } label: {
                                    Group {
                                        if let url = anc.authorAvatarURL {
                                            AsyncImage(url: url) { phase in
                                                switch phase {
                                                case .empty: Circle().fill(Color.secondary.opacity(0.15)).overlay(ProgressView())
                                                case .success(let image): image.resizable().scaledToFill()
                                                case .failure: Circle().fill(Color.secondary.opacity(0.2))
                                                @unknown default: Circle().fill(Color.secondary.opacity(0.2))
                                                }
                                            }
                                        } else { Circle().fill(Color.secondary.opacity(0.2)) }
                                    }
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                                }
                                .buttonStyle(.plain)

                                // Content → Post detail
                                NavigationLink {
                                    PostDetailView(post: anc, viewModel: ThreadViewModel(session: session, root: anc))
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(anc.authorDisplayName?.isEmpty == false ? anc.authorDisplayName! : anc.authorHandle)
                                            .font(.headline.weight(.semibold))
                                            .lineLimit(1)
                                        Text(anc.text)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 10)
                            Divider()
                        }
                    }
                    .padding(.bottom, 8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    header
                    content
                    if let quoted = post.quotedPost {
                        QuotedPostCard(post: quoted, onOpenPost: { q in
                            postSelection = q
                        }, onOpenProfile: { net, handle in
                            profileRoute = ProfileRoute(network: net, handle: handle)
                        })
                    }
                    if !post.media.isEmpty { mediaGrid }
                    actionBar
                }
                .id("focusedPost")

                Divider().padding(.vertical, 6)
                repliesSection
                    .animation(nil, value: viewModel.items.count)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $initialPosition, anchor: .top)
            .navigationTitle("Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "bluesky" && url.host == "profile" {
                    let comps = url.pathComponents.filter { $0 != "/" }
                    if let handle = comps.first { profileRoute = ProfileRoute(network: .bluesky, handle: handle); return .handled }
                }
                if let scheme = url.scheme, (scheme == "https" || scheme == "http"), let host = url.host {
                    let path = url.path
                    // Status first, then profile
                    if let statusID = extractMastoStatusID(fromPath: path) {
                        Task { await openMastodonStatus(host: host, id: statusID, originalURL: url) }
                        return .handled
                    }
                    if path.hasPrefix("/@") {
                        let username = String(path.dropFirst(2))
                        profileRoute = ProfileRoute(network: .mastodon(instance: host), handle: username)
                        return .handled
                    }
                    if path.hasPrefix("/users/") {
                        let comps = path.split(separator: "/").map(String.init)
                        if comps.count >= 2 {
                            profileRoute = ProfileRoute(network: .mastodon(instance: host), handle: comps[1])
                            return .handled
                        }
                    }
                    if host == "bsky.app" && path.hasPrefix("/profile/") {
                        let handle = String(path.dropFirst("/profile/".count))
                        profileRoute = ProfileRoute(network: .bluesky, handle: handle)
                        return .handled
                    }
                    // Non-profile web links
                    if session.openLinksInApp {
                        #if canImport(SafariServices) && canImport(UIKit)
                        safariURL = url
                        return .handled
                        #else
                        return .systemAction
                        #endif
                    }
                }
                return .systemAction
            })
            .fullScreenCover(item: $imageViewer) { (selection: ImageViewerState) in
                ImageViewer(post: selection.post, startIndex: selection.index)
            }
            #if canImport(SafariServices)
            .sheet(isPresented: Binding(get: { safariURL != nil }, set: { if !$0 { safariURL = nil } })) {
                if let url = safariURL { SafariView(url: url) }
            }
            #endif
            .task {
                await viewModel.load()
            }
            .navigationDestination(item: $profileRoute) { route in
                ProfileView(network: route.network, handle: route.handle, session: session)
            }
            .navigationDestination(item: $postSelection) { p in
                PostDetailView(post: p, viewModel: ThreadViewModel(session: session, root: p))
            }
    }

    // MARK: - Header
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar → Profile (tappable)
            NavigationLink {
                ProfileView(network: post.network, handle: post.authorHandle, session: session)
            } label: {
                avatar
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("@\(post.authorHandle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Image(systemName: networkIconName)
                    .foregroundStyle(.secondary)
                Text(fullDate(post.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var avatar: some View {
        Group {
            if let url = post.authorAvatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Circle().fill(Color.secondary.opacity(0.15)).overlay(ProgressView())
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else { placeholder }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle().fill(Color.secondary.opacity(0.2))
            .overlay(
                Text(String(post.authorHandle.prefix(1).uppercased()))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
            )
    }

    // MARK: - Content
    private var content: some View {
        Text(post.text)
            .font(.body)
            .textSelection(.enabled)
    }

    // MARK: - Media
    private var mediaGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(Array(post.media.enumerated()), id: \.offset) { idx, m in
                Button {
                    imageViewer = ImageViewerState(post: post, index: idx)
                } label: {
                    AsyncImage(url: m.url) { phase in
                        switch phase {
                        case .empty:
                            Rectangle().fill(Color.secondary.opacity(0.1)).overlay(ProgressView())
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Rectangle().fill(Color.secondary.opacity(0.15)).overlay(Image(systemName: "photo"))
                        @unknown default:
                            Rectangle().fill(Color.secondary.opacity(0.15))
                        }
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Replies
    private var repliesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Replies")
                .font(.headline)
                .padding(.bottom, 8)

            if viewModel.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 12)
            }

            ForEach(viewModel.items) { item in
                HStack(alignment: .top, spacing: 10) {
                    // Avatar → Profile
                    NavigationLink {
                        ProfileView(network: item.post.network, handle: item.post.authorHandle, session: session)
                    } label: {
                        Group {
                            if let url = item.post.authorAvatarURL {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty: Circle().fill(Color.secondary.opacity(0.15)).overlay(ProgressView())
                                    case .success(let image): image.resizable().scaledToFill()
                                    case .failure: Circle().fill(Color.secondary.opacity(0.2))
                                    @unknown default: Circle().fill(Color.secondary.opacity(0.2))
                                    }
                                }
                            } else { Circle().fill(Color.secondary.opacity(0.2)) }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    // Content → Post detail
                    NavigationLink {
                        PostDetailView(post: item.post, viewModel: ThreadViewModel(session: session, root: item.post))
                    } label: {
                        PostRow(post: item.post, showAvatar: false, onOpenProfile: { net, handle in
                            profileRoute = ProfileRoute(network: net, handle: handle)
                        }, onOpenPost: { q in
                            postSelection = q
                        })
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .padding(.leading, CGFloat(item.depth) * 16)
                .padding(.vertical, 4)

                Divider().padding(.leading, CGFloat(item.depth) * 16)
            }

            if let err = viewModel.error {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Actions
    private var actionBar: some View {
        HStack(spacing: 24) {
            Button { /* TODO: reply composer */ } label: { Image(systemName: "bubble.left") }
            Button { Task { await handleRepost() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.squarepath").foregroundStyle(state.isReposted ? Color.accentColor : Color.secondary)
                    if let s = Formatters.shortCount(state.repostCount) { Text(s).accessibilityHidden(true) }
                }
            }
            Button { Task { await handleLike() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: state.isLiked ? "heart.fill" : "heart").foregroundStyle(state.isLiked ? Color.accentColor : Color.secondary)
                    if let s = Formatters.shortCount(state.likeCount) { Text(s).accessibilityHidden(true) }
                }
            }
            if case .mastodon = post.network {
                Button { Task { await handleBookmark() } } label: {
                    Image(systemName: state.isBookmarked ? "bookmark.fill" : "bookmark").foregroundStyle(state.isBookmarked ? Color.accentColor : Color.secondary)
                }
            }
            Spacer()
        }
        .font(.title3)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
        .buttonStyle(.plain)
    }

    @MainActor private func handleLike() async {
        let s = state
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
            do { let rkey = try await session.blueskyClient?.like(post: post); withAnimation { session.updateState(for: post.id) { $0.bskyLikeRkey = rkey ?? prevRkey } } } catch {
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

    @MainActor private func handleRepost() async {
        let s = state
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
            case .mastodon(_):
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
            do { let rkey = try await session.blueskyClient?.repost(post: post); withAnimation { session.updateState(for: post.id) { $0.bskyRepostRkey = rkey ?? prevRkey } } } catch {
                Haptics.notify(.error)
                withAnimation { session.updateState(for: post.id) { $0.isReposted = prev; $0.repostCount = prevCount } }
            }
        case .mastodon(_):
            do { _ = try await session.mastodonClient?.repost(post: post) } catch {
                Haptics.notify(.error)
                withAnimation { session.updateState(for: post.id) { $0.isReposted = prev; $0.repostCount = prevCount } }
            }
        }
    }

    @MainActor private func handleBookmark() async {
        guard case .mastodon = post.network else { return }
        let prev = state.isBookmarked
        if state.isBookmarked {
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

    private var state: PostInteractionState { session.state(for: post) }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { share() } label: { Image(systemName: "square.and.arrow.up") }
        }
    }

    private func share() { /* TODO: add share link per-network */ }

    // MARK: - Helpers
    private var networkIconName: String {
        switch post.network {
        case .bluesky: return "cloud"
        case .mastodon(_): return "dot.radiowaves.left.and.right"
        }
    }

    private var displayName: String {
        post.authorDisplayName?.isEmpty == false ? post.authorDisplayName! : post.authorHandle
    }

    private func fullDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    private func extractMastoStatusID(fromPath path: String) -> String? {
        let comps = path.split(separator: "/").map(String.init)
        if comps.count >= 2, comps[0].hasPrefix("@") {
            let last = comps.last!
            if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: last)) { return last }
        }
        if let idx = comps.firstIndex(of: "statuses"), idx + 1 < comps.count {
            let cand = comps[idx + 1]
            if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: cand)) { return cand }
        }
        return nil
    }

    @MainActor
    private func openMastodonStatus(host: String, id: String, originalURL: URL?) async {
        let client: MastodonClient
        if let c = session.mastodonClient, c.baseURL.host == host { client = c }
        else if let base = URL(string: "https://\(host)") { client = MastodonClient(baseURL: base, accessToken: "") }
        else { return }
        if let post = try? await client.fetchStatus(id: id) {
            postSelection = post
            return
        }
        // Fallback
        #if canImport(SafariServices) && canImport(UIKit)
        if session.openLinksInApp { safariURL = originalURL }
        #endif
    }
}
